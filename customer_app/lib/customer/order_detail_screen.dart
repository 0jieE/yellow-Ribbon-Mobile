import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order_model.dart';
import '../services/api_client.dart';
import '../services/order_service.dart';
import '../services/payment_service.dart';
import '../services/pending_payment.dart';
import '../utils/route_path.dart';
import 'order_status.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// How often the detail endpoint is re-read while the rider is on the road.
/// The rider app pings its position every 10–15s, so polling faster than this
/// would return the same coordinates and waste the customer's data.
const _pollInterval = Duration(seconds: 12);

/// How often an unpaid online order is re-read. PayMongo's webhook usually
/// lands within seconds of the customer authorising, and this is the screen
/// they come back to, so it should flip to paid without a manual refresh.
const _paymentPollInterval = Duration(seconds: 4);

/// The least time between two payment status checks. Each one is a server
/// call to the gateway, so it runs on every other payment poll rather than
/// every one.
const _syncEvery = Duration(seconds: 8);

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _orders = OrderService();
  final _payments = PaymentService();

  AppOrder? _order;
  String? _error;
  bool _loading = true;
  bool _cancelling = false;
  bool _paying = false;

  /// Guards against a slow poll overlapping the next tick.
  bool _refreshing = false;

  Timer? _pollTimer;
  Duration? _pollEvery;
  DateTime? _lastSync;
  GoogleMapController? _mapController;

  /// The camera is fitted once, then left alone so a poll does not yank the
  /// map back while the customer is panning around.
  bool _cameraFitted = false;

  /// The decoded route, and the encoded string it came from.
  ///
  /// The polyline arrives with every poll. Re-decoding an unchanged value
  /// every 12 seconds would hand the map a fresh point list each time and
  /// make it flicker, so it is only decoded when the string actually changes.
  List<LatLng> _routePoints = const [];
  String? _decodedFrom;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final order = await _fetch();
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
      });
      _syncRoute(order);
      _syncPolling(order);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
      _stopPolling();
    }
  }

  /// Background refresh: no spinner, and a transient failure is swallowed so
  /// a dropped packet does not replace a live map with an error screen.
  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;

    try {
      final order = await _fetch();
      if (!mounted) return;
      final wasAwaitingPayment = _order?.awaitingPayment ?? false;
      setState(() => _order = order);
      _syncRoute(order);
      _syncPolling(order);
      if (wasAwaitingPayment && (order.payment?.isPaid ?? false)) {
        _snack(
          "${order.paymentMethodLabel} payment confirmed. "
          "Your order is with the store.",
        );
      }
    } on ApiException {
      // Keep showing the last good state; the next tick will try again.
    } finally {
      _refreshing = false;
    }
  }

  /// Reads the order — first asking the gateway where an unpaid online
  /// order stands.
  ///
  /// Maya sends no webhook, and PayMongo's GCash webhook can be missed (the
  /// server asleep, a failed delivery), so the server is asked to check with
  /// the gateway directly. That is throttled, since every sync is a call to
  /// GCash or Maya, and a failure is not fatal — the order is still shown and
  /// the next tick asks again.
  Future<AppOrder> _fetch() async {
    var order = await _orders.fetchOrder(widget.orderId);

    final last = _lastSync;
    final due = last == null || DateTime.now().difference(last) >= _syncEvery;
    if (order.awaitingPayment && order.isOnlinePayment && due) {
      _lastSync = DateTime.now();
      try {
        final sync = await _payments.sync(order.id);
        if (sync.paid) order = await _orders.fetchOrder(widget.orderId);
      } on ApiException {
        // Gateway unreachable this time; the next poll tries again.
      }
    }
    return order;
  }

  /// Polls while there is something to watch for: the gateway settling an
  /// unpaid online order, or the rider moving once it is out for delivery.
  /// Stops otherwise — which covers both terminal statuses, since
  /// `delivered` and `cancelled` are neither.
  void _syncPolling(AppOrder order) {
    final every = order.awaitingPayment
        ? _paymentPollInterval
        : order.isOutForDelivery
            ? _pollInterval
            : null;

    if (every == null) {
      _stopPolling();
    } else if (every != _pollEvery) {
      _stopPolling();
      _pollEvery = every;
      _pollTimer = Timer.periodic(every, (_) => _refresh());
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollEvery = null;
  }

  /// Reopens the gateway's page — PayMongo's for GCash, Maya's for Maya —
  /// for an order that is still unpaid after a failed or abandoned attempt.
  /// The backend hands back the same link while it is live and issues a
  /// fresh one once it is dead.
  Future<void> _pay() async {
    final order = _order;
    if (order == null) return;

    setState(() => _paying = true);
    try {
      // The return deep link carries no order id; this is how it finds us.
      await PendingPayment.instance.remember(order.id);
      final session = await _payments.startCheckout(order.id);
      final launched = await launchUrl(
        Uri.parse(session.checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _snack("The ${order.paymentMethodLabel} page could not be opened.");
      }
    } on ApiException catch (e) {
      _snack(e.message);
      await _refresh();
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Re-decodes the route only when the encoded string has actually changed.
  void _syncRoute(AppOrder order) {
    if (order.routePolyline == _decodedFrom) return;

    _decodedFrom = order.routePolyline;
    _routePoints = RoutePath.decode(order.routePolyline);
    // A route appearing for the first time is worth framing.
    _cameraFitted = false;
    _fitCamera(order);
  }

  Future<void> _confirmCancel() async {
    final order = _order;
    if (order == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Cancel this order?"),
        content: Text(
          "${order.orderNumber} will be cancelled. This cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Keep order"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Cancel order"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);

    try {
      final updated = await _orders.cancelOrder(order.id);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _cancelling = false;
      });
      _syncPolling(updated);
      _snack("${updated.orderNumber} has been cancelled.");
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      // The window can close between the button rendering and the tap —
      // the server is the authority, so re-read rather than argue.
      _snack(e.message);
      await _refresh();
    }
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

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: Text( 
          order != null ? "Order ${order.orderNumber}" : "Order",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: _amber,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (order != null && !order.isTerminal)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
              tooltip: "Refresh",
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _DetailError(message: _error!, onRetry: _load)
              : _buildBody(order!),
    );
  }

  Widget _buildBody(AppOrder order) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusHeader(order: order),

          const SizedBox(height: 14),

          // LIVE TRACKING — only while a rider is actually carrying it.
          _TrackingSection(
            order: order,
            routePoints: _routePoints,
            onMapCreated: (controller) {
              _mapController = controller;
              _fitCamera(order);
            },
            onRecentre: () => _centreOnRider(order),
          ),

          const SizedBox(height: 14),

          _DeliverySection(order: order),

          const SizedBox(height: 14),

          _PaymentSection(
            order: order,
            paying: _paying,
            onPay: _pay,
          ),

          const SizedBox(height: 14),

          _ItemsSection(order: order),

          const SizedBox(height: 14),

          _TimelineSection(order: order),

          if (order.canCancel) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _cancelling ? null : _confirmCancel,
                icon: _cancelling
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cancel_outlined),
                label: const Text(
                  "CANCEL ORDER",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "You can cancel until the store accepts your order.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Snaps the camera onto the rider.
  ///
  /// The rider is the only thing moving, so "where is my food" is answered by
  /// putting them in the middle at street level. Falls back to framing what
  /// is known when no position has been reported yet.
  Future<void> _centreOnRider(AppOrder order) async {
    final controller = _mapController;
    if (controller == null) return;

    final rider = order.riderLocation;
    if (rider == null) {
      _cameraFitted = false;
      await _fitCamera(order);
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(rider.latitude, rider.longitude),
        RoutePath.minZoom,
      ),
    );
  }

  /// Frames the route, the rider and the destination — whichever exist.
  Future<void> _fitCamera(AppOrder order) async {
    final controller = _mapController;
    if (controller == null || _cameraFitted) return;
    if (!order.hasDestination) return;

    final destination = LatLng(order.deliveryLatitude!, order.deliveryLongitude!);
    final rider = order.riderLocation;

    _cameraFitted = true;

    final points = <LatLng>[
      destination,
      ..._routePoints,
      if (rider != null) LatLng(rider.latitude, rider.longitude),
    ];

    // Null means the box is too small to zoom to — two points effectively on
    // top of each other — so centre instead.
    final bounds = RoutePath.bounds(points);

    if (bounds == null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(destination, RoutePath.minZoom),
      );
      return;
    }

    try {
      // moveCamera rather than animateCamera: the zoom has to be read back
      // straight after, and an in-flight animation would report the old one.
      await controller.moveCamera(CameraUpdate.newLatLngBounds(bounds, 72));

      // Fitting a long route zooms out past the point where streets are
      // legible. Never sit wider than minZoom; the zoom controls are there
      // to pull back and see the whole route.
      if (await controller.getZoomLevel() < RoutePath.minZoom) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            // The rider is the moving part, so that is what the customer
            // wants in frame — not the midpoint of a road they are not on.
            rider == null
                ? RoutePath.centreOf(bounds)
                : LatLng(rider.latitude, rider.longitude),
            RoutePath.minZoom,
          ),
        );
      }
    } on Exception {
      // The map can refuse a bounds move before it has finished laying out.
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(destination, RoutePath.minZoom),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    final style = OrderStatusStyle.of(order.displayStatus);
    final done = OrderProgress.completed(
      order.status,
      deliveryStatus: order.deliveryStatus,
    );

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(status: order.displayStatus),
              const Spacer(),
              Text(
                "₱${order.total.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                  color: Colors.deepOrange,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Named stage, then the bar. The same pairing as the orders list,
          // so the two screens agree at a glance.
          Row(
            children: [
              Expanded(
                child: Text(
                  OrderProgress.labelFor(
                    order.status,
                    deliveryStatus: order.deliveryStatus,
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: done == null ? Colors.grey : style.colour,
                  ),
                ),
              ),
              Text(
                done == null
                    ? '—'
                    : 'Step $done of ${OrderProgress.total}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              ),
            ],
          ),

          const SizedBox(height: 7),

          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: done == null ? 0 : done / OrderProgress.total,
              minHeight: 8,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation(
                order.status == 'cancelled'
                    ? Colors.grey.shade400
                    : style.colour,
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            "Placed ${Dates.full(order.placedAt)}",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (order.awaitingPayment) ...[
            const SizedBox(height: 8),
            Text(
              "This order reaches the kitchen once your "
              "${order.paymentMethodLabel} payment is confirmed.",
              style: const TextStyle(fontSize: 12, color: Color(0xFFB26A00)),
            ),
          ],
          if (order.status == 'cancelled' &&
              (order.cancelReason?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            Text(
              "Reason: ${order.cancelReason}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}

/// The map, or a message explaining why there is nothing to track yet.
class _TrackingSection extends StatelessWidget {
  const _TrackingSection({
    required this.order,
    required this.routePoints,
    required this.onMapCreated,
    required this.onRecentre,
  });

  final AppOrder order;

  /// Decoded once by the parent and reused across polls, so an unchanged
  /// route is not rebuilt every 12 seconds.
  final List<LatLng> routePoints;

  final void Function(GoogleMapController) onMapCreated;
  final VoidCallback onRecentre;

  /// What to say when `rider_location` is null — which is the normal state
  /// before a rider is assigned and again once the delivery finishes.
  String get _absentMessage {
    switch (order.status) {
      case 'pending_payment':
        return "Tracking starts once your payment is confirmed.";
      case 'pending':
        return "Waiting for the store to accept your order.";
      case 'confirmed':
        return "The store has accepted your order. A rider is assigned once "
            "it is ready.";
      case 'preparing':
        return "Your order is being prepared.";
      case 'ready':
        return "Your order is ready and waiting for a rider.";
      case 'out_for_delivery':
        return "Your rider has collected your order. The map and arrival "
            "time appear once they set off — this page refreshes itself.";
      case 'delivered':
        return "Delivered ${Dates.full(order.deliveredAt)}.";
      case 'cancelled':
        return "This order was cancelled.";
      default:
        return "Live tracking is not available for this order.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final rider = order.riderLocation;

    // No rider position, or no destination to draw it against.
    if (rider == null || !order.hasDestination) {
      final style = OrderStatusStyle.of(order.displayStatus);

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // Tinted to the status, so this reads as part of the progress
          // rather than as a missing map.
          color: style.colour.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: style.colour.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(style.icon, color: style.colour),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _absentMessage,
                style: TextStyle(fontSize: 13, height: 1.4, color: _ink),
              ),
            ),
          ],
        ),
      );
    }

    final destination = LatLng(order.deliveryLatitude!, order.deliveryLongitude!);
    final riderPoint = LatLng(rider.latitude, rider.longitude);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 260,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: riderPoint,
                    zoom: RoutePath.minZoom,
                  ),
                  onMapCreated: onMapCreated,
                  // The road the rider is actually driving, rather than
                  // leaving the customer to imagine a line between two dots.
                  polylines: {
                    if (routePoints.length > 1)
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: routePoints,
                        color: const Color(0xFF00695C),
                        width: 5,
                        startCap: Cap.roundCap,
                        endCap: Cap.roundCap,
                        jointType: JointType.round,
                      ),
                  },
                  markers: {
                    Marker(
                      markerId: const MarkerId('rider'),
                      position: riderPoint,
                      infoWindow: InfoWindow(
                        title: rider.riderName,
                        snippet: rider.vehicleType.isEmpty
                            ? 'Your rider'
                            : rider.vehicleType,
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueAzure,
                      ),
                    ),
                    Marker(
                      markerId: const MarkerId('destination'),
                      position: destination,
                      infoWindow: const InfoWindow(title: 'Delivery address'),
                    ),
                  },
                  zoomControlsEnabled: true,
                  myLocationButtonEnabled: false,
                  liteModeEnabled: false,
                ),
                // Bottom-LEFT deliberately: Android puts its zoom controls
                // bottom-right, and this button used to sit on top of them.
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: FloatingActionButton.small(
                    heroTag: 'recentre_tracking',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    tooltip: "Centre on rider",
                    onPressed: onRecentre,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.delivery_dining, color: Color(0xFF00796B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rider.riderName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    "Updated ${Dates.since(rider.updatedAt)}",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // The backend computes an arrival estimate at the moment the
              // rider sets off, and never earlier — one Routes call per leg
              // actually driven. Before that there is genuinely no number,
              // so say so rather than showing a stale or invented one.
              if (order.hasEta)
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      "Arriving in about ${order.etaMinutes} min",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (order.etaAt != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        "(~${Dates.time(order.etaAt)})",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                )
              else
                Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Arrival time appears once your rider sets off.",
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeliverySection extends StatelessWidget {
  const _DeliverySection({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: "Delivery",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(order.deliveryAddress),
          if (order.deliveryNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              "Note: ${order.deliveryNotes}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}

/// How the order is paid for, and — once the gateway has settled it — the
/// invoice, the gateway's reference and whose wallet paid. After a cancel,
/// where the refund stands.
class _PaymentSection extends StatelessWidget {
  const _PaymentSection({
    required this.order,
    required this.paying,
    required this.onPay,
  });

  final AppOrder order;
  final bool paying;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final payment = order.payment;
    final refund = payment?.refund;
    final method = order.paymentMethodLabel;

    return _Card(
      title: "Payment",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                order.isOnlinePayment
                    ? Icons.account_balance_wallet_outlined
                    : Icons.payments_outlined,
                size: 18,
                color: Colors.grey.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  switch (order.paymentType) {
                    'gcash' => "GCash",
                    'maya' => "Maya Wallet",
                    _ => "Cash on delivery",
                  },
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _PaymentChip(order: order),
            ],
          ),

          if (payment != null) ...[
            const SizedBox(height: 12),
            _row("Invoice", payment.invoiceNumber),
            if (payment.payer != null) _row("Paid from", payment.payer!),
            if (payment.paymongoReference.isNotEmpty)
              _row(
                payment.isPaid
                    ? "$method payment"
                    : "$method reference",
                payment.paymongoReference,
                mono: true,
              ),
            if (payment.isPaid) ...[
              _row("Amount paid", "₱${payment.amountPaid.toStringAsFixed(2)}"),
              _row("Paid on", Dates.full(payment.paidAt)),
            ],
          ],

          if (refund != null) ...[
            const SizedBox(height: 12),
            _RefundNote(refund: refund, method: order.paymentMethodLabel),
          ],

          if (order.awaitingPayment) ...[
            const SizedBox(height: 12),
            Text(
              order.paymentStatus == 'failed'
                  ? "The last ${order.paymentMethodLabel} attempt did not go "
                      "through."
                  : "Waiting for your $method payment to be confirmed. "
                      "This updates by itself.",
              style: const TextStyle(fontSize: 12, color: Color(0xFFB26A00)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: paying ? null : onPay,
                icon: paying
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  "PAY WITH ${order.paymentMethodLabel.toUpperCase()}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: _ink,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            // Selectable so the reference can be read off or copied and
            // matched against the gateway's dashboard.
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the money stands after a paid order was cancelled.
class _RefundNote extends StatelessWidget {
  const _RefundNote({required this.refund, required this.method});

  final RefundInfo refund;
  final String method;

  @override
  Widget build(BuildContext context) {
    final amount = "₱${refund.amount.toStringAsFixed(2)}";
    final (icon, colour, text) = switch (refund.status) {
      'refunded' => (
          Icons.check_circle_outline,
          const Color(0xFF2E7D32),
          "$amount was refunded to your $method on "
              "${Dates.full(refund.refundedAt)}.",
        ),
      'failed' => (
          Icons.error_outline,
          const Color(0xFFC62828),
          "Your $amount refund has not gone through yet. The store has been "
              "told and will retry it.",
        ),
      _ => (
          Icons.hourglass_top,
          const Color(0xFFB26A00),
          "Refund of $amount to your $method is on the way.",
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: colour)),
          ),
        ],
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  const _PaymentChip({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    final (label, colour) = switch (order.paymentStatus) {
      // Stays "paid" until the gateway confirms the refund.
      'paid' when order.payment?.refund != null =>
        ("Refund pending", const Color(0xFFB26A00)),
      'paid' => ("Paid", const Color(0xFF2E7D32)),
      'failed' => ("Failed", const Color(0xFFC62828)),
      'refunded' => ("Refunded", Colors.grey.shade700),
      _ when order.awaitingPayment => ("Awaiting payment", const Color(0xFFB26A00)),
      _ when order.paymentType == 'cod' => ("Pay on delivery", Colors.grey.shade700),
      _ => ("Unpaid", Colors.grey.shade700),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: colour,
        ),
      ),
    );
  }
}

class _ItemsSection extends StatelessWidget {
  const _ItemsSection({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: "Items",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      "${item.quantity}×",
                      style: const TextStyle(fontWeight: FontWeight.bold),
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
          const Divider(),
          _totalRow("Subtotal", order.subtotal),
          _totalRow("Delivery fee", order.deliveryFee),
          const Divider(),
          _totalRow("Total", order.total, isBold: true),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            "₱${value.toStringAsFixed(2)}",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isBold ? Colors.deepOrange : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

/// The `status_logs` audit trail, oldest first as the backend orders it.
class _TimelineSection extends StatelessWidget {
  const _TimelineSection({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    if (order.statusLogs.isEmpty) {
      return const SizedBox.shrink();
    }

    return _Card(
      title: "Progress",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...List.generate(order.statusLogs.length, (index) {
            final log = order.statusLogs[index];
            final style = OrderStatusStyle.of(log.status);
            final isLast = index == order.statusLogs.length - 1;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dot and connector.
                  Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(top: 3),
                        decoration: BoxDecoration(
                          color: style.colour,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: Colors.grey.shade300,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            style.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            Dates.full(log.changedAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

/// A white card, optionally with the amber-accented header the rest of the
/// app uses for section titles.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final heading = title;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: heading == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 15,
                      decoration: BoxDecoration(
                        color: _amber,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      heading.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                child,
              ],
            ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text("Retry")),
          ],
        ),
      ),
    );
  }
}
