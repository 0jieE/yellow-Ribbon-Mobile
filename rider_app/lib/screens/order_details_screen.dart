import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/delivery_model.dart';
import '../services/api_client.dart';
import '../services/delivery_service.dart';
import '../services/location_pinger.dart';
import '../utils/route_path.dart';
import '../widgets/delivery_status.dart';
import 'delivery_map_screen.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// How often the delivery re-reads itself while it is still live.
///
/// The kitchen moves the order to `ready` from the admin app, and the backend
/// refuses `picked_up` before that. Polling means the rider sees it turn
/// ready on its own instead of tapping a button that 400s.
const _pollInterval = Duration(seconds: 15);

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.deliveryId});

  final int deliveryId;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  final _deliveries = DeliveryService();
  final _picker = ImagePicker();

  Delivery? _delivery;
  String? _error;
  bool _loading = true;

  /// The server no longer shows this delivery to this rider (404) — the
  /// store handed the order to someone else before pickup.
  bool _gone = false;
  bool _working = false;

  GoogleMapController? _mapController;

  /// Guards against a slow poll overlapping the next tick.
  bool _refreshing = false;
  Timer? _pollTimer;

  /// The decoded route, and the encoded string it came from.
  ///
  /// Cached so a poll every 15 seconds does not re-decode an unchanged
  /// polyline and hand the map a fresh object each time, which makes it
  /// flicker.
  List<LatLng> _routePoints = const [];
  String? _decodedFrom;

  /// The camera is fitted once, then left alone so the rider can pan without
  /// being yanked back. The recentre button clears this.
  bool _cameraFitted = false;

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
      final delivery = await _deliveries.fetchOne(widget.deliveryId);
      if (!mounted) return;
      setState(() {
        _delivery = delivery;
        _loading = false;
      });
      _syncRoute(delivery);
      _syncPolling(delivery);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _gone = e.statusCode == 404;
        _error = e.message;
      });
      _stopPolling();
    }
  }

  /// Background re-read: no spinner, and a transient failure keeps the last
  /// good state rather than throwing the rider onto an error screen mid-job.
  Future<void> _silentRefresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;

    try {
      final delivery = await _deliveries.fetchOne(widget.deliveryId);
      if (!mounted) return;
      setState(() => _delivery = delivery);
      _syncRoute(delivery);
      _syncPolling(delivery);
    } on ApiException catch (e) {
      // A 404 is not a blip: the delivery was moved to another rider, so
      // stop showing it as theirs. Anything else keeps the last good state
      // and the next tick tries again.
      if (e.statusCode == 404 && mounted) {
        setState(() => _gone = true);
        _stopPolling();
      }
    } finally {
      _refreshing = false;
    }
  }

  /// Polls while the delivery is still live, and stops once it is delivered
  /// or failed — nothing further will change after that.
  void _syncPolling(Delivery delivery) {
    if (delivery.isTerminal) {
      _stopPolling();
    } else {
      _pollTimer ??= Timer.periodic(_pollInterval, (_) => _silentRefresh());
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Re-decodes the route only when the encoded string has actually changed.
  void _syncRoute(Delivery delivery) {
    final encoded = delivery.order.routePolyline;
    if (encoded == _decodedFrom) return;

    _decodedFrom = encoded;
    _routePoints = RoutePath.decode(encoded);
    // A route arriving for the first time is worth framing.
    _cameraFitted = false;
    _fitCamera(delivery);
  }

  /// Frames the whole route, or just the destination when there is no route.
  Future<void> _fitCamera(Delivery delivery) async {
    final controller = _mapController;
    final order = delivery.order;
    if (controller == null || _cameraFitted || !order.hasDestination) return;

    _cameraFitted = true;

    final destination = LatLng(
      order.deliveryLatitude!,
      order.deliveryLongitude!,
    );

    final bounds = RoutePath.bounds(_routePoints);

    if (bounds == null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(destination, RoutePath.minZoom),
      );
      return;
    }

    try {
      // moveCamera rather than animateCamera: the zoom has to be read back
      // straight after, and an in-flight animation would report the old one.
      await controller.moveCamera(CameraUpdate.newLatLngBounds(bounds, 60));

      // A long route fits at a zoom where street names stop rendering, which
      // is no use to someone trying to find a door. Never sit wider than
      // minZoom; the zoom controls are there to pull back.
      if (await controller.getZoomLevel() < RoutePath.minZoom) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            // Start of the route is where the rider set off from, so it
            // frames their end of the leg rather than the middle of it.
            // Their live position is one tap away on the my-location button.
            _routePoints.isNotEmpty
                ? _routePoints.first
                : RoutePath.centreOf(bounds),
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

  void _apply(Delivery updated) {
    setState(() => _delivery = updated);
    _syncRoute(updated);

    // Finishing the delivery is the point at which polling can stop.
    _syncPolling(updated);

    // Only ever starts the pinger from here, never stops it. This screen sees
    // one delivery, so it cannot tell whether the rider has others still
    // running — stopping on this one finishing would go dark on the rest.
    // AssignedOrdersScreen re-syncs against the full list when this pops.
    if (updated.isActive) LocationPinger.instance.start();
  }

  // -- actions ---------------------------------------------------------

  Future<void> _changeStatus(String status) async {
    final delivery = _delivery;
    if (delivery == null) return;

    String reason = '';

    if (status == 'failed') {
      final entered = await _askFailureReason();
      if (entered == null) return;
      reason = entered;
    } else if (status == 'delivered') {
      final confirmed = await _confirmDelivered(delivery);
      if (confirmed != true) return;
    }

    setState(() => _working = true);

    try {
      final updated = await _deliveries.updateStatus(
        delivery.id,
        status,
        failureReason: reason,
      );
      if (!mounted) return;
      setState(() => _working = false);
      _apply(updated);
      _snack("Marked ${DeliveryStatusStyle.of(status).label.toLowerCase()}.");

      // The photo is the evidence the drop-off happened, so it is offered
      // immediately rather than left to the rider to remember.
      if (status == 'delivered' && !updated.hasProof) {
        await _offerProofUpload();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      // Covers the "order is not ready for pickup yet" refusal and any
      // illegal transition. The server is the authority, so re-read. A 404
      // means it was reassigned, which the re-read explains on screen.
      if (e.statusCode != 404) _snack(e.message);
      await _load();
    }
  }

  Future<bool?> _confirmDelivered(Delivery delivery) {
    final collect = delivery.order.amountToCollect;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Mark as delivered?"),
        content: Text(
          collect > 0
              ? "Confirm you have handed over the order and collected "
                  "₱${collect.toStringAsFixed(2)} in cash."
              : "Confirm you have handed over the order. This one is already "
                  "paid — collect nothing.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Not yet"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Delivered"),
          ),
        ],
      ),
    );
  }

  Future<String?> _askFailureReason() async {
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Report a failed delivery"),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: "What happened? e.g. nobody home",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text("Report failed"),
          ),
        ],
      ),
    );

    controller.dispose();
    return reason;
  }

  Future<void> _offerProofUpload() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Proof of delivery",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text("Take a photo"),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Choose from gallery"),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text("Not now"),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;
    await _uploadProof(source);
  }

  Future<void> _uploadProof(ImageSource source) async {
    final delivery = _delivery;
    if (delivery == null) return;

    XFile? photo;
    try {
      photo = await _picker.pickImage(
        source: source,
        // The photo is evidence, not a portfolio piece. Shrinking it keeps
        // the upload quick on a phone connection.
        maxWidth: 1600,
        imageQuality: 80,
      );
    } on Exception {
      _snack("Could not open the camera.");
      return;
    }

    if (photo == null || !mounted) return;

    setState(() => _working = true);

    try {
      final updated = await _deliveries.uploadProof(delivery.id, photo.path);
      if (!mounted) return;
      setState(() => _working = false);
      _apply(updated);
      _snack("Proof of delivery uploaded.");
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _snack(e.message);
    }
  }

  /// Hands off to Google Maps for turn-by-turn directions.
  ///
  /// Uses the universal `google.navigation:` intent first — it starts
  /// navigation directly — and falls back to the web directions URL, which
  /// resolves to the Maps app when installed and the browser otherwise.
  Future<void> _navigate() async {
    final order = _delivery?.order;
    if (order == null || !order.hasDestination) {
      _snack("This order has no delivery coordinates.");
      return;
    }

    final lat = order.deliveryLatitude!;
    final lng = order.deliveryLongitude!;

    final navigation = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final web = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
      '&travelmode=driving',
    );

    try {
      if (await canLaunchUrl(navigation)) {
        await launchUrl(navigation, mode: LaunchMode.externalApplication);
        return;
      }
      final launched =
          await launchUrl(web, mode: LaunchMode.externalApplication);
      if (!launched) _snack("Could not open Google Maps.");
    } on Exception {
      _snack("Could not open Google Maps.");
    }
  }

  /// The route map carries only what the rider has actually collected, so the
  /// hand-off is offered for those and hidden for an order still on the
  /// counter — better than a button that opens a map the stop is not on.
  bool _isOnRouteMap(Delivery delivery) =>
      delivery.status == 'picked_up' || delivery.status == 'in_transit';

  /// Opens the route map with this stop's sheet already up.
  Future<void> _openRouteMap(Delivery delivery) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryMapScreen(focusDeliveryId: delivery.id),
      ),
    );
    if (!mounted) return;

    // Start Delivery lives on that screen too, so the status has quite
    // possibly moved while it was open.
    await _silentRefresh();
  }

  Future<void> _callCustomer() async {
    final phone = _delivery?.order.customerPhone ?? '';
    if (phone.isEmpty) {
      _snack("No phone number on this order.");
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched = await launchUrl(uri);
      if (!launched) _snack("Could not start the call.");
    } on Exception {
      _snack("Could not start the call.");
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // -- build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final delivery = _delivery;

    return Scaffold(
      appBar: AppBar(
        title: Text(delivery?.order.orderNumber ?? "Delivery"),
        actions: [
          if (delivery != null && !_gone)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: "Refresh",
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _gone
              ? _ReassignedState(orderNumber: delivery?.order.orderNumber)
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _buildBody(delivery!),
    );
  }

  Widget _buildBody(Delivery delivery) {
    final order = delivery.order;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // STATUS
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  StatusBadge(status: delivery.status),
                  const Spacer(),
                  if (delivery.status == 'delivered')
                    Text(
                      "+₱${delivery.riderEarnings.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // AMOUNT TO COLLECT — the number the rider must not get wrong.
          _CollectCard(order: order),

          const SizedBox(height: 14),

          // MAP + NAVIGATE
          _DestinationMap(
            order: order,
            routePoints: _routePoints,
            onMapCreated: (controller) {
              _mapController = controller;
              _fitCamera(delivery);
            },
            onRecentre: () {
              _cameraFitted = false;
              _fitCamera(delivery);
            },
            onNavigate: _navigate,
            onShowOnMap:
                _isOnRouteMap(delivery) ? () => _openRouteMap(delivery) : null,
          ),

          const SizedBox(height: 14),

          // CUSTOMER
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Customer",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  _infoRow(Icons.person_outline, order.customerName),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 18, color: Colors.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          order.customerPhone.isEmpty
                              ? "No phone number"
                              : order.customerPhone,
                        ),
                      ),
                      if (order.customerPhone.isNotEmpty)
                        TextButton.icon(
                          onPressed: _callCustomer,
                          icon: const Icon(Icons.call, size: 18),
                          label: const Text("Call"),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _infoRow(Icons.location_on_outlined, order.deliveryAddress),
                  if (order.deliveryNotes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.sticky_note_2_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(order.deliveryNotes)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ITEMS
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Order",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
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
                          Expanded(child: Text(item.menuName)),
                          Text("₱${item.lineSubtotal.toStringAsFixed(2)}"),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Order total",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "₱${order.total.toStringAsFixed(2)}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // PROOF
          _ProofCard(
            delivery: delivery,
            onUpload: _working ? null : _offerProofUpload,
          ),

          const SizedBox(height: 20),

          // STATUS ACTIONS — built from next_statuses, so the app can never
          // offer a transition the server would refuse.
          ..._buildActions(delivery),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _buildActions(Delivery delivery) {
    // The store cancelled it while it was still on this rider's list. Nothing
    // may be picked up, delivered or failed any more.
    if (delivery.orderCancelled) {
      return [
        _ActionNote(
          icon: Icons.cancel_outlined,
          colour: const Color(0xFFC62828),
          text: "The store cancelled ${delivery.order.orderNumber}. "
              "There is nothing to pick up or deliver.",
        ),
      ];
    }

    if (delivery.status == 'failed') {
      final reason = delivery.failureReason?.trim() ?? '';
      return [
        _ActionNote(
          icon: Icons.report_problem_outlined,
          colour: const Color(0xFFC62828),
          text: reason.isEmpty
              ? "This delivery failed."
              : "This delivery failed. Reason: $reason",
        ),
      ];
    }

    // Assigned, but the kitchen is not done. The rider sees why, and the
    // pickup button stays visible but disabled so the next step is obvious.
    final blocked = delivery.pickupBlockedReason;
    if (blocked != null) {
      return [
        _ActionNote(
          icon: Icons.hourglass_top,
          colour: const Color(0xFFB26A00),
          text: "$blocked You can pick it up once the store marks it "
              "ready — you will get a notification.",
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: null,
          icon: Icon(DeliveryStatusStyle.of('picked_up').icon),
          label: const Text("Waiting for the store"),
        ),
      ];
    }

    if (delivery.nextStatuses.isEmpty) {
      return [
        Center(
          child: Text(
            "This delivery is ${DeliveryStatusStyle.of(delivery.status).label.toLowerCase()}.",
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ];
    }

    // `failed` sits alongside the happy path once the food is collected; it
    // is shown last and styled as the destructive option. Before pickup
    // there is nothing to fail — a rider who cannot make it calls the store,
    // which hands the order to someone else.
    final forward =
        delivery.nextStatuses.where((s) => s != 'failed').toList();
    final canFail = delivery.nextStatuses.contains('failed') &&
        delivery.status != 'assigned';

    return [
      ...forward.map(
        (status) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ElevatedButton.icon(
            onPressed: _working ? null : () => _changeStatus(status),
            icon: _working
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Icon(DeliveryStatusStyle.of(status).icon),
            label: Text(DeliveryStatusStyle.actionLabel(status)),
          ),
        ),
      ),

      if (canFail)
        OutlinedButton.icon(
          onPressed: _working ? null : () => _changeStatus('failed'),
          icon: const Icon(Icons.report_problem_outlined),
          label: const Text("Report failed delivery"),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
    ];
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

class _CollectCard extends StatelessWidget {
  const _CollectCard({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final collects = order.collectsCash;

    return Card(
      color: collects ? Colors.deepOrange.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              collects ? Icons.payments : Icons.check_circle,
              color: collects ? Colors.deepOrange : Colors.green,
              size: 30,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collects ? "Collect on delivery" : "Already paid",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    collects
                        ? "₱${order.amountToCollect.toStringAsFixed(2)}"
                        : "Paid by ${switch (order.paymentType) {
                            'gcash' => 'GCash',
                            'maya' => 'Maya',
                            _ => 'the customer',
                          }} — collect nothing",
                    style: TextStyle(
                      fontSize: collects ? 24 : 13,
                      fontWeight:
                          collects ? FontWeight.bold : FontWeight.normal,
                      color: collects ? Colors.deepOrange : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationMap extends StatelessWidget {
  const _DestinationMap({
    required this.order,
    required this.routePoints,
    required this.onMapCreated,
    required this.onNavigate,
    required this.onRecentre,
    required this.onShowOnMap,
  });

  final DeliveryOrder order;

  /// Decoded once by the parent and reused across polls, so an unchanged
  /// route does not redraw every 15 seconds.
  final List<LatLng> routePoints;

  final void Function(GoogleMapController) onMapCreated;
  final VoidCallback onNavigate;
  final VoidCallback onRecentre;

  /// Opens the route map on this stop. Null when the delivery is not on that
  /// map — it carries only what the rider is physically holding.
  final VoidCallback? onShowOnMap;

  @override
  Widget build(BuildContext context) {
    if (!order.hasDestination) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.location_off, color: Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "No map coordinates on this order — use the written "
                  "address:\n${order.deliveryAddress}",
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final destination = LatLng(
      order.deliveryLatitude!,
      order.deliveryLongitude!,
    );

    final hasRoute = routePoints.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 250,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: destination,
                    zoom: RoutePath.minZoom,
                  ),
                  onMapCreated: onMapCreated,
                  markers: {
                    Marker(
                      markerId: const MarkerId('destination'),
                      position: destination,
                      infoWindow: InfoWindow(
                        title: 'Deliver here',
                        snippet: order.deliveryAddress,
                      ),
                    ),
                  },
                  polylines: {
                    if (hasRoute)
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: routePoints,
                        // Dark enough to read over both road and satellite
                        // tiles; amber would vanish on a yellow road.
                        color: const Color(0xFF00695C),
                        width: 6,
                        startCap: Cap.roundCap,
                        endCap: Cap.roundCap,
                        jointType: JointType.round,
                      ),
                  },
                  // The blue dot appears once the location permission has
                  // been granted for the pings. Google's own centre-on-me
                  // button comes with it — it sits top-right, clear of the
                  // zoom controls, and is the reliable way back to the
                  // rider's live position.
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                ),

                // Bottom-LEFT deliberately: Android puts its zoom controls
                // bottom-right, and this button used to sit on top of them.
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: FloatingActionButton.small(
                    heroTag: 'recentre_route',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    tooltip: "Show the whole route",
                    onPressed: onRecentre,
                    child: const Icon(Icons.route),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        _RouteSummary(order: order, routePoints: routePoints),

        const SizedBox(height: 10),

        Row(
          children: [
            // Turn-by-turn stays with Google Maps — this map is for
            // orientation.
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.navigation, size: 20),
                label: const Text("Google Navigate"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                ),
              ),
            ),
            if (onShowOnMap != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShowOnMap,
                  icon: const Icon(Icons.map_outlined, size: 20),
                  label: const Text("Route map"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: BorderSide(color: Colors.grey.shade400),
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Distance and ETA for the leg, or an explanation of why there is neither.
class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.order, required this.routePoints});

  final DeliveryOrder order;
  final List<LatLng> routePoints;

  @override
  Widget build(BuildContext context) {
    // Both the route and the ETA are written when the delivery goes
    // in_transit, so before that neither exists — the normal state while a
    // delivery is assigned or picked up, not a failure.
    if (routePoints.length < 2) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _amber.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.route_outlined, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "The route and arrival time appear once you start the "
                "delivery.",
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
              ),
            ),
          ],
        ),
      );
    }

    final km = RoutePath.distanceKm(routePoints);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _metric(
              icon: Icons.straighten,
              label: "Distance",
              value: km < 1
                  ? "${(km * 1000).round()} m"
                  : "${km.toStringAsFixed(1)} km",
            ),
          ),
          Container(width: 1, height: 32, color: Colors.white24),
          Expanded(
            child: _metric(
              icon: Icons.schedule,
              label: "Arrival",
              value: order.etaMinutes == null
                  ? "—"
                  : "${order.etaMinutes} min",
              caption: order.etaAt == null ? null : Dates.time(order.etaAt),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric({
    required IconData icon,
    required String label,
    required String value,
    String? caption,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: _amber),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Colors.white60),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (caption != null)
              Text(
                "~$caption",
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProofCard extends StatelessWidget {
  const _ProofCard({required this.delivery, required this.onUpload});

  final Delivery delivery;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Proof of delivery",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),

            if (delivery.hasProof) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  delivery.proofOfDelivery!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 80,
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const Text("Photo uploaded"),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            if (!delivery.canUploadProof)
              const Text(
                "Available once you have picked the order up.",
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              )
            else
              OutlinedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.camera_alt),
                label: Text(
                  delivery.hasProof ? "Replace photo" : "Upload photo",
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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

/// Shown when the store moved this order to another rider before pickup.
class _ReassignedState extends StatelessWidget {
  const _ReassignedState({this.orderNumber});

  final String? orderNumber;

  @override
  Widget build(BuildContext context) {
    final which = orderNumber == null ? "This order" : orderNumber!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              "$which is no longer assigned to you. The store gave it to "
              "another rider.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Back to my orders"),
            ),
          ],
        ),
      ),
    );
  }
}

/// A coloured note in place of, or above, the action buttons.
class _ActionNote extends StatelessWidget {
  const _ActionNote({
    required this.icon,
    required this.colour,
    required this.text,
  });

  final IconData icon;
  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: colour, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
