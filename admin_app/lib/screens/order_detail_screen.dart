import 'package:flutter/material.dart';

import '../models/admin_order_model.dart';
import '../services/admin_order_service.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/assign_rider_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/order_status.dart';
import '../widgets/section_card.dart';

/// `GET /api/admin/orders/{id}/` with the actions the admin can take on it.
///
/// Pops with the updated order so the queue can refresh that one row without
/// refetching the whole page.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _orders = AdminOrderService();

  AdminOrder? _order;
  String? _error;
  bool _loading = true;
  bool _working = false;

  /// Set once anything changes, so the queue knows to take the updated copy.
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final order = await _orders.fetchOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _changeStatus(String status) async {
    final order = _order;
    if (order == null) return;

    String reason = '';

    if (status == 'cancelled') {
      final entered = await _askCancelReason(order);
      if (entered == null) return;
      reason = entered;
    }

    setState(() => _working = true);

    try {
      final updated = await _orders.updateStatus(
        order.id,
        status,
        cancelReason: reason,
      );
      if (!mounted) return;
      setState(() {
        _order = updated;
        _working = false;
        _dirty = true;
      });
      _snack("${updated.orderNumber} is now ${OrderStatusStyle.of(status).label.toLowerCase()}.");
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      // An illegal jump comes back naming what is allowed next. The server
      // is the authority, so re-read rather than argue with it.
      _snack(e.message);
      await _load();
    }
  }

  Future<String?> _askCancelReason(AdminOrder order) async {
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Cancel ${order.orderNumber}?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("This cannot be undone."),
            if (order.payment?.isPaid ?? false) ...[
              const SizedBox(height: 8),
              Text(
                order.paymentType == 'cod'
                    ? "This order was already paid in cash."
                    : "The customer's "
                        "₱${order.payment!.amountPaid.toStringAsFixed(2)} "
                        "${order.paymentType == 'maya' ? 'Maya' : 'GCash'} "
                        "payment will be refunded automatically.",
                style: const TextStyle(fontSize: 13, color: kMuted),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Reason (optional)",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Keep order"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text("Cancel order"),
          ),
        ],
      ),
    );

    controller.dispose();
    return reason;
  }

  Future<void> _assignRider() async {
    final order = _order;
    if (order == null) return;

    final riderId = await showAssignRiderSheet(
      context,
      orderNumber: order.orderNumber,
    );
    if (riderId == null || !mounted) return;

    setState(() => _working = true);

    try {
      final updated = await _orders.assignRider(order.id, riderId);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _working = false;
        _dirty = true;
      });
      _snack("Assigned to ${updated.rider?.name ?? 'rider'}.");
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _showRefusal(e.message);
    }
  }

  Future<void> _retryRefund() async {
    final order = _order;
    if (order == null) return;

    setState(() => _working = true);
    try {
      final updated = await _orders.retryRefund(order.id);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _working = false;
        _dirty = true;
      });
      final refund = updated.payment?.refund;
      _snack(switch (refund?.status) {
        'refunded' => "Refund completed.",
        'failed' => "The gateway refused the refund again.",
        _ => "Refund requested. Waiting for the gateway to confirm.",
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _snack(e.message);
      await _load();
    }
  }

  void _showRefusal(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.block, color: Colors.red, size: 32),
        title: const Text("Cannot assign"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _dirty ? _order : null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(order?.orderNumber ?? "Order"),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _dirty ? _order : null),
          ),
          actions: [
            if (order != null)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
                tooltip: "Refresh",
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? EmptyState(
                    icon: Icons.cloud_off,
                    title: "Could not load this order",
                    message: _error!,
                    onRetry: _load,
                  )
                : _buildBody(order!),
      ),
    );
  }

  Widget _buildBody(AdminOrder order) {
    return RefreshIndicator(
      color: kAmber,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // HEADLINE — status and money, on ink.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kInk,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(status: order.status),
                    const Spacer(),
                    Text(
                      "₱${order.total.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _inkLine(
                  Icons.schedule,
                  "Placed ${Dates.full(order.placedAt)}",
                ),
                const SizedBox(height: 5),
                _inkLine(
                  order.paymentType == 'cod'
                      ? Icons.payments_outlined
                      : Icons.account_balance_wallet_outlined,
                  "${switch (order.paymentType) {
                    'gcash' => 'GCash',
                    'maya' => 'Maya',
                    _ => 'Cash on delivery',
                  }} · ${order.paymentStatus}",
                ),
                if (order.status == 'cancelled' &&
                    (order.cancelReason?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 5),
                  _inkLine(
                    Icons.cancel_outlined,
                    "Reason: ${order.cancelReason}",
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // PAYMENT — the invoice and PayMongo reference the webhook wrote.
          _PaymentCard(
            order: order,
            onRetryRefund: _working ? null : _retryRefund,
          ),

          const SizedBox(height: 14),

          // RIDER — assign button, or who has it.
          _RiderCard(
            order: order,
            onAssign: _working ? null : _assignRider,
          ),

          const SizedBox(height: 14),

          SectionCard(
            title: "Customer",
            icon: Icons.person_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconLine(Icons.person_outline, order.customerName),
                const SizedBox(height: 9),
                IconLine(
                  Icons.phone_outlined,
                  order.customerPhone.isEmpty
                      ? "No phone number"
                      : order.customerPhone,
                  muted: order.customerPhone.isEmpty,
                ),
                const SizedBox(height: 9),
                IconLine(Icons.location_on_outlined, order.deliveryAddress),
                if (order.deliveryNotes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: kAmber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.sticky_note_2_outlined,
                          size: 16,
                          color: kInk,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            order.deliveryNotes,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          SectionCard(
            title: "Items",
            icon: Icons.receipt_long_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...order.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            "${item.quantity}×",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.menuName),
                              Text(
                                "₱${item.unitPrice.toStringAsFixed(2)} each",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text("₱${item.lineSubtotal.toStringAsFixed(2)}"),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 18),
                DetailRow(
                  "Subtotal",
                  "₱${order.subtotal.toStringAsFixed(2)}",
                ),
                DetailRow(
                  "Delivery fee",
                  "₱${order.deliveryFee.toStringAsFixed(2)}",
                ),
                const Divider(height: 18),
                DetailRow(
                  "Total",
                  "₱${order.total.toStringAsFixed(2)}",
                  emphasise: true,
                ),
              ],
            ),
          ),

          if (order.statusLogs.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: "History",
              icon: Icons.history,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...order.statusLogs.map(
                    (log) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            OrderStatusStyle.of(log.status).icon,
                            size: 16,
                            color: OrderStatusStyle.of(log.status).colour,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              OrderStatusStyle.of(log.status).label,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            Dates.full(log.changedAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: kMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // STATUS ACTIONS — built from next_statuses, so the app can never
          // offer a transition the server would refuse.
          ..._buildActions(order),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _buildActions(AdminOrder order) {
    if (order.nextStatuses.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            "This order is ${OrderStatusStyle.of(order.status).label.toLowerCase()} — nothing further to do.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontSize: 13),
          ),
        ),
      ];
    }

    // Cancellation is available from nearly every state; it goes last and is
    // styled as the destructive option.
    final forward =
        order.nextStatuses.where((s) => s != 'cancelled').toList();
    final canCancel = order.nextStatuses.contains('cancelled');

    return [
      ...forward.map(
        (status) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            onPressed: _working ? null : () => _changeStatus(status),
            icon: _working
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kInk,
                    ),
                  )
                : Icon(OrderStatusStyle.of(status).icon, size: 20),
            label: Text(OrderStatusStyle.actionLabel(status)),
          ),
        ),
      ),

      if (canCancel)
        OutlinedButton.icon(
          onPressed: _working ? null : () => _changeStatus('cancelled'),
          icon: const Icon(Icons.cancel_outlined, size: 20),
          label: const Text("Cancel order"),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFC62828),
            side: const BorderSide(color: Color(0xFFC62828)),
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
    ];
  }

  /// One muted line inside the ink headline card.
  Widget _inkLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
      ],
    );
  }
}

/// How the order is paid, and the proof once it is: the invoice, whose
/// wallet paid, and the gateway id to match against that gateway's
/// dashboard. Also what the gateway kept, and — after a cancel — where the
/// refund stands, with a retry when it is stuck.
class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.order, required this.onRetryRefund});

  final AdminOrder order;
  final VoidCallback? onRetryRefund;

  @override
  Widget build(BuildContext context) {
    final type = order.paymentType;
    final isOnline = type == 'gcash' || type == 'maya';
    final method = type == 'maya' ? "Maya" : "GCash";
    final payment = order.payment;
    final refund = payment?.refund;

    final (label, colour) = switch (order.paymentStatus) {
      'paid' when refund != null && !refund.isDone =>
        ("Refund ${refund.status}", const Color(0xFFB26A00)),
      'paid' => ("Paid", const Color(0xFF2E7D32)),
      'failed' => ("Failed", const Color(0xFFC62828)),
      'refunded' => ("Refunded", kMuted),
      _ when order.status == 'pending_payment' =>
        ("Awaiting payment", const Color(0xFFB26A00)),
      _ when !isOnline => ("Collect on delivery", kMuted),
      _ => ("Unpaid", kMuted),
    };

    // A cancelled order that was paid online and whose money is not back
    // with the customer yet: the backend accepts a retry for exactly these.
    final canRetryRefund = order.status == 'cancelled' &&
        isOnline &&
        (payment?.isPaid ?? false) &&
        !(refund?.isDone ?? false);

    return SectionCard(
      title: "Payment",
      icon: isOnline
          ? Icons.account_balance_wallet_outlined
          : Icons.payments_outlined,
      trailing: TagPill(label: label, colour: colour),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailRow(
            "Method",
            switch (type) {
              'gcash' => "GCash",
              'maya' => "Maya Wallet",
              _ => "Cash on delivery",
            },
          ),
          if (payment != null) ...[
            DetailRow("Invoice", payment.invoiceNumber),
            if (payment.payer != null) DetailRow("Paid from", payment.payer!),
            if (payment.paymongoReference.isNotEmpty)
              DetailRow(
                payment.isPaid
                    ? "$method payment"
                    : "$method reference",
                payment.paymongoReference,
              ),
            if (payment.isPaid) ...[
              DetailRow(
                "Amount paid",
                "₱${payment.amountPaid.toStringAsFixed(2)}",
              ),
              DetailRow("Paid on", Dates.full(payment.paidAt)),
              if (isOnline && payment.fee != null)
                DetailRow(
                  "Gateway fee",
                  "−₱${payment.fee!.toStringAsFixed(2)}",
                ),
              if (payment.netAmount != null)
                DetailRow(
                  "Net to store",
                  "₱${payment.netAmount!.toStringAsFixed(2)}",
                  emphasise: true,
                ),
            ],
          ] else if (order.status == 'pending_payment')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "The customer has not opened the $method checkout yet.",
                style: const TextStyle(fontSize: 12.5, color: kMuted),
              ),
            ),

          if (refund != null) ...[
            const SizedBox(height: 10),
            _RefundBox(refund: refund),
          ],

          if (canRetryRefund) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRetryRefund,
              icon: const Icon(Icons.replay, size: 19),
              label: Text(
                refund == null
                    ? "Refund the customer"
                    : refund.status == 'failed'
                        ? "Retry refund"
                        : "Check refund status",
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RefundBox extends StatelessWidget {
  const _RefundBox({required this.refund});

  final RefundInfo refund;

  @override
  Widget build(BuildContext context) {
    final amount = "₱${refund.amount.toStringAsFixed(2)}";
    final (icon, colour, title) = switch (refund.status) {
      'refunded' => (
          Icons.check_circle_outline,
          const Color(0xFF2E7D32),
          "$amount refunded ${Dates.full(refund.refundedAt)}",
        ),
      'failed' => (
          Icons.error_outline,
          const Color(0xFFC62828),
          "Refund of $amount failed",
        ),
      _ => (
          Icons.hourglass_top,
          const Color(0xFFB26A00),
          "Refund of $amount requested, waiting for the gateway",
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: colour),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colour,
                  ),
                ),
                if (refund.reference != null)
                  Text(
                    refund.reference!,
                    style: const TextStyle(fontSize: 11.5, color: kMuted),
                  ),
                if (refund.status == 'failed' && refund.error != null)
                  Text(
                    refund.error!,
                    style: const TextStyle(fontSize: 11.5, color: kMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.order, required this.onAssign});

  final AdminOrder order;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final rider = order.rider;

    return SectionCard(
      title: "Rider",
      icon: Icons.delivery_dining,
      child: rider != null
          ? Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kAmber,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delivery_dining, color: kInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rider.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                      Text(
                        rider.phone.isEmpty ? "@${rider.username}" : rider.phone,
                        style: const TextStyle(fontSize: 12, color: kMuted),
                      ),
                    ],
                  ),
                ),
                TagPill(
                  label: rider.deliveryStatus.replaceAll('_', ' '),
                  colour: const Color(0xFF00695C),
                ),
              ],
            )
          : order.canAssignRider
              ? OutlinedButton.icon(
                  onPressed: onAssign,
                  icon: const Icon(Icons.person_add_alt, size: 19),
                  label: const Text("Assign a rider"),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                  ),
                )
              : Text(
                  order.status == 'pending_payment'
                      ? "This order has not been paid for yet. It can be "
                          "assigned once the payment is confirmed."
                      : "An order that is "
                          "${OrderStatusStyle.of(order.status).label.toLowerCase()}"
                          " cannot be assigned.",
                  style: const TextStyle(fontSize: 12.5, color: kMuted),
                ),
    );
  }
}
