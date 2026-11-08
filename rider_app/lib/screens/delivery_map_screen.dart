import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/delivery_model.dart';
import '../services/api_client.dart';
import '../services/delivery_service.dart';
import '../services/location_pinger.dart';
import '../services/osrm_service.dart';
import '../utils/numbered_marker.dart';
import '../utils/route_path.dart';
import '../widgets/delivery_status.dart';
import 'order_details_screen.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// The committed route the backend wrote from Google Routes. Solid.
const _officialRouteColour = Color(0xFF00695C);

/// A leg drawn on demand from OSRM. Dashed, and a different hue, because it
/// is a guess at a route nobody has committed to yet — the rider should never
/// mistake one for the other.
const _previewRouteColour = Color(0xFF7B1FA2);

/// Matches the assigned-orders list, for the same reason: the kitchen and the
/// admin move things while the rider is looking at this screen.
const _pollInterval = Duration(seconds: 20);

/// Room at the top of the map for the attribution chip.
const double _topInset = 44;

/// Where a tapped pin comes to rest, as a fraction of the map's height.
///
/// 0.5 would be the dead centre, which sits behind the sheet. This puts the
/// pin in the middle of the top three quarters — well clear of the details,
/// and still far enough down that the street above it is visible.
const double _pinAnchorFraction = 0.375;

/// Stand-in for the sheet's height until it has been laid out and measured.
const double _assumedSheetHeight = 300;

/// Every stop the rider is physically carrying, on one map.
///
/// Scope is deliberately narrower than the Orders tab. `assigned` means an
/// order has been given to this rider but is still on the counter — there is
/// nothing to plan a route around. This screen answers "I have four bags in
/// the box, which one do I run first?", so it shows only what has actually
/// been collected: `picked_up`, plus the one `in_transit` leg if there is one.
///
/// The Direction button draws any stop's route without leaving the app. That
/// matters because the backend writes a route only for the single delivery
/// that is `in_transit` — every other bag in the box is a blank until the
/// rider commits to it, which is precisely the wrong time to find out one of
/// them is twice as far as it looked.
class DeliveryMapScreen extends StatefulWidget {
  const DeliveryMapScreen({super.key, this.focusDeliveryId});

  /// Opened for one particular stop — its sheet is up and its pin centred as
  /// soon as the stops load, rather than the rider having to find it among
  /// the others. Null when reached from the tab bar.
  final int? focusDeliveryId;

  @override
  State<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends State<DeliveryMapScreen>
    with WidgetsBindingObserver {
  final _deliveries = DeliveryService();
  final _osrm = OsrmService.instance;

  GoogleMapController? _mapController;
  Timer? _pollTimer;

  /// Collected stops, in the order they were assigned — which is also the
  /// order the pins are numbered in.
  List<Delivery> _stops = const [];

  /// Held deliveries the backend has no coordinates for. They cannot be
  /// mapped, so they are counted and named rather than silently dropped.
  List<Delivery> _unmappable = const [];

  Set<Marker> _markers = const {};

  /// Decoded `route_polyline` per delivery, with the encoded string it came
  /// from, so a poll every 20 seconds does not hand the map fresh objects for
  /// an unchanged route and make it flicker.
  final Map<int, List<LatLng>> _officialRoutes = {};
  final Map<int, String> _decodedFrom = {};

  int? _selectedId;

  /// The stop whose OSRM leg is currently drawn, or null when none is.
  ///
  /// Generating a leg is an explicit act — the Direction button — rather than
  /// something that happens on selection. That keeps the demo server's load
  /// to legs the rider actually asked for, and makes the button's effect
  /// obvious: line appears, line goes away.
  int? _previewFor;

  RoutePreview? _preview;
  List<LatLng> _previewPoints = const [];
  bool _previewLoading = false;

  bool _loading = true;
  bool _refreshing = false;
  bool _starting = false;
  String? _error;

  /// The map's height, cached from layout so the camera maths can run from
  /// an async callback that has no BuildContext to measure with.
  double _mapHeight = 0;

  /// The sheet is measured rather than assumed: its height moves with the
  /// address length and the blocked-delivery warning, and a padding constant
  /// that is wrong by 60px is exactly what buries the zoom controls.
  final GlobalKey _sheetKey = GlobalKey();
  double _sheetHeight = 0;

  /// What the map treats as covered at the bottom.
  double get _bottomInset =>
      _selectedId == null ? 12 : (_sheetHeight > 0 ? _sheetHeight : _assumedSheetHeight);

  /// The camera frames everything once, then leaves the rider alone to pan.
  bool _cameraFitted = false;

  /// [DeliveryMapScreen.focusDeliveryId] is honoured on the first load only —
  /// after that the rider is in charge of what is selected.
  bool _focusApplied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Opened for a specific stop: skip framing every pin, because the focus
    // is about to move the camera anyway and two moves in a row looks broken.
    if (widget.focusDeliveryId != null) _cameraFitted = true;

    _load();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _silentRefresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _silentRefresh();
  }

  Delivery? get _selected {
    for (final stop in _stops) {
      if (stop.id == _selectedId) return stop;
    }
    return null;
  }

  /// The one leg under way, if any. The backend allows at most one per rider.
  Delivery? get _inTransit {
    for (final stop in _stops) {
      if (stop.status == 'in_transit') return stop;
    }
    return null;
  }

  int _numberOf(Delivery delivery) => _stops.indexOf(delivery) + 1;

  static LatLng _positionOf(Delivery delivery) => LatLng(
        delivery.order.deliveryLatitude!,
        delivery.order.deliveryLongitude!,
      );

  // -- data --------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _fetch();
      if (!mounted) return;
      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// Background poll: a dropped request keeps the last good map rather than
  /// replacing a working screen with an error.
  Future<void> _silentRefresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;

    try {
      await _fetch();
      if (!mounted) return;
      setState(() {
        _error = null;
        _loading = false;
      });
    } on ApiException {
      // The next tick tries again.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _fetch() async {
    final all = await _deliveries.fetchActive();

    // The full list, not the filtered one — the pinger's job is to track a
    // rider with any active work, including orders still on the counter.
    LocationPinger.instance.syncWith(all);

    final held = all
        .where((d) => d.status == 'picked_up' || d.status == 'in_transit')
        .toList();

    if (!mounted) return;

    setState(() {
      _stops = held.where((d) => d.order.hasDestination).toList();
      _unmappable = held.where((d) => !d.order.hasDestination).toList();

      // A stop that has been delivered while this screen was open should not
      // keep its sheet open over an empty patch of map.
      if (_selectedId != null && _selected == null) _clearSelection();
    });

    _syncOfficialRoutes();
    await _rebuildMarkers();
    _fitAllStops();
    await _applyInitialFocus();
  }

  /// Opens the sheet for the stop this screen was pushed for.
  Future<void> _applyInitialFocus() async {
    final wanted = widget.focusDeliveryId;
    if (wanted == null || _focusApplied || !mounted) return;
    _focusApplied = true;

    for (final stop in _stops) {
      if (stop.id == wanted) {
        await _select(stop);
        return;
      }
    }

    // Delivered from the other screen while this was loading, or held
    // without coordinates. Better said out loud than leaving the rider
    // hunting for a pin that was never going to be there.
    _snack("That stop is not on the map right now.");
  }

  /// Re-decodes a committed route only when its encoded string has changed.
  void _syncOfficialRoutes() {
    final live = <int>{};

    for (final stop in _stops) {
      live.add(stop.id);
      final encoded = stop.order.routePolyline;
      if (_decodedFrom[stop.id] == encoded) continue;

      _decodedFrom[stop.id] = encoded;
      _officialRoutes[stop.id] = RoutePath.decode(encoded);
    }

    // Drop anything no longer in hand, so a long shift does not accumulate
    // decoded routes for deliveries that finished hours ago.
    _officialRoutes.removeWhere((id, _) => !live.contains(id));
    _decodedFrom.removeWhere((id, _) => !live.contains(id));
  }

  Future<void> _rebuildMarkers() async {
    final markers = <Marker>{};

    for (var i = 0; i < _stops.length; i++) {
      final stop = _stops[i];

      final style = stop.id == _selectedId
          ? StopPinStyle.selected
          : stop.status == 'in_transit'
              ? StopPinStyle.inTransit
              : StopPinStyle.held;

      markers.add(
        Marker(
          markerId: MarkerId('stop_${stop.id}'),
          position: _positionOf(stop),
          icon: await NumberedMarker.pin(number: i + 1, style: style),
          // No info window: the sheet carries every field, and a bubble would
          // cover the pin it belongs to along with its neighbours.
          onTap: () => _select(stop),
          // The open stop draws over its neighbours, which matters when two
          // doors on the same street put their pins on top of each other.
          zIndexInt: stop.id == _selectedId ? 2 : 1,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _markers = markers);
  }

  // -- selection ---------------------------------------------------------

  Future<void> _select(Delivery stop) async {
    setState(() {
      _selectedId = stop.id;
      // A drawn leg belongs to the stop it was generated for, so it goes when
      // the rider moves to another pin.
      _clearPreview();
    });

    await _rebuildMarkers();

    // Always the stop itself, never the route it belongs to. Framing a whole
    // committed route puts the camera on the middle of the road the rider is
    // travelling, which reads as the map wandering off somewhere unrelated
    // to the pin they just tapped. Seeing the whole leg is what Direction is
    // for.
    await _centreOnStop(stop);
  }

  /// Brings a tapped stop to rest in the upper part of the map.
  ///
  /// Not the dead centre: the sheet covers the bottom of the screen, so a pin
  /// centred in the full viewport ends up behind the details.
  Future<void> _centreOnStop(Delivery stop) async {
    // The sheet's padding is applied in the same setState that opened it, and
    // the SDK only hears about it when that frame is built. Moving the camera
    // any earlier centres against the old, full-height viewport — which is
    // the other half of the "it goes somewhere else" behaviour.
    await _nextFrame();

    final controller = _mapController;
    if (controller == null) return;

    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        _anchored(_positionOf(stop)),
        RoutePath.minZoom,
      ),
    );
  }

  /// Resolves once the frame currently being built has been rendered.
  Future<void> _nextFrame() {
    final rendered = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => rendered.complete());
    return rendered.future;
  }

  /// Places [point] at [_pinAnchorFraction] down the map rather than in the
  /// middle of whatever the SDK considers visible.
  LatLng _anchored(LatLng point) {
    if (_mapHeight <= 0) return point;

    // Where the SDK is going to put the target: the middle of what is left
    // after the padding it has been given.
    final visibleCentre = (_topInset + _mapHeight - _bottomInset) / 2;
    final wanted = _mapHeight * _pinAnchorFraction;

    return RoutePath.raisePin(
      point,
      byPixels: visibleCentre - wanted,
      zoom: RoutePath.minZoom,
    );
  }

  void _clearPreview() {
    _previewFor = null;
    _preview = null;
    _previewPoints = const [];
    _previewLoading = false;
  }

  void _clearSelection() {
    _selectedId = null;
    _clearPreview();
  }

  Future<void> _closeSheet() async {
    setState(_clearSelection);
    await _rebuildMarkers();
  }

  /// Draws the leg from where the rider is standing to this stop.
  ///
  /// This is the whole point of going to OSRM. The backend only writes a
  /// route when a delivery goes `in_transit`, and it writes exactly one —
  /// so a rider holding four bags has no way to see the shape of any of them
  /// before committing. OSRM answers that for a stop in any state, without
  /// spending Google Routes quota on a leg nobody has agreed to yet.
  ///
  /// Tapping again clears the line.
  Future<void> _toggleDirection(Delivery stop) async {
    if (_previewFor == stop.id) {
      setState(_clearPreview);
      return;
    }

    setState(() {
      _clearPreview();
      _previewLoading = true;
    });

    final origin = await _currentPosition();

    // The rider may have tapped another pin while this was in flight.
    if (!mounted || _selectedId != stop.id) return;

    if (origin == null) {
      setState(() => _previewLoading = false);
      _snack(
        "Could not read your location, so there is nothing to draw the route "
        "from. Check that location is turned on.",
      );
      return;
    }

    final preview = await _osrm.previewLeg(
      deliveryId: stop.id,
      from: origin,
      to: _positionOf(stop),
    );

    if (!mounted || _selectedId != stop.id) return;

    if (preview == null) {
      setState(() => _previewLoading = false);
      // A tap that visibly does nothing is worse than a line of text. The
      // stop's details stay put — only the route is missing.
      _snack("Could not work out a route to this stop right now.");
      return;
    }

    setState(() {
      _previewFor = stop.id;
      _preview = preview;
      _previewPoints = RoutePath.decode(preview.polyline);
      _previewLoading = false;
    });

    // Swapping the spinner for the distance readout makes the sheet a little
    // taller, which changes the map's padding. Fit after that has been laid
    // out, or the leg is framed against a viewport that no longer exists.
    await _nextFrame();
    await _fitTo(_previewPoints);
  }

  /// The rider's position, or null when it cannot be had.
  ///
  /// Prefers the cached fix: [LocationPinger] calls `getCurrentPosition`
  /// every 12 seconds whenever there is active work, so on this screen a
  /// last-known fix is usually seconds old and costs nothing. Anything older
  /// than a minute is refetched rather than trusted.
  Future<LatLng?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Time-boxed for the same reason as the pinger's: Android shows one
        // runtime dialog at a time and silently drops a second request,
        // which would leave this awaiting a callback that never comes.
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 20));
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null &&
          DateTime.now().difference(cached.timestamp) <
              const Duration(minutes: 1)) {
        return LatLng(cached.latitude, cached.longitude);
      }

      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 20));

      return LatLng(fresh.latitude, fresh.longitude);
    } on TimeoutException {
      return null;
    } on Exception {
      return null;
    }
  }

  // -- camera ------------------------------------------------------------

  void _fitAllStops() {
    if (_cameraFitted || _stops.isEmpty) return;
    _cameraFitted = true;
    _fitTo(_stops.map(_positionOf).toList());
  }

  /// Frames [points], whatever zoom that takes.
  ///
  /// Deliberately *not* clamped to [RoutePath.minZoom]. That clamp belongs to
  /// the single-destination maps, where the camera would otherwise sit too
  /// far out to read a street name. Applying it to a fitted route does real
  /// damage: a 2 km leg cannot fit at zoom 16, so the clamp fires, and the
  /// camera lands at zoom 16 on the middle of the route — a stretch of road
  /// with neither the rider nor the customer on screen. Asking to see a whole
  /// leg means seeing the whole leg.
  ///
  /// A single point has no extent to fit, so that case still uses minZoom.
  Future<void> _fitTo(List<LatLng> points) async {
    final controller = _mapController;
    if (controller == null || points.isEmpty) return;

    final bounds = RoutePath.bounds(points);

    if (bounds == null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, RoutePath.minZoom),
      );
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 70),
      );
    } on Exception {
      // The map refuses a bounds move before it has finished laying out.
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, RoutePath.minZoom),
      );
    }
  }

  // -- actions -----------------------------------------------------------

  Future<void> _startDelivery(Delivery stop) async {
    setState(() => _starting = true);

    try {
      final updated = await _deliveries.updateStatus(stop.id, 'in_transit');
      if (!mounted) return;

      // The estimate has been superseded by the route the backend just
      // committed, so it is dropped rather than left to be shown again.
      _osrm.forget(stop.id);

      setState(() {
        _starting = false;
        _clearPreview();
      });

      // Refetch so the pin restyles and `route_polyline` arrives.
      await _silentRefresh();
      if (!mounted) return;

      _fitTo(_officialRoutes[stop.id] ?? const []);
      LocationPinger.instance.start();
      _snack("On the way with ${updated.order.orderNumber}.");
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      await _showStartRefusal(e);
      // The server is the authority on what state things are in — re-read
      // rather than guessing from the error.
      await _silentRefresh();
    }
  }

  /// The exact sentence the serializer wrote.
  ///
  /// The shared error handler prefixes field errors with the field name, so
  /// `message` arrives as "status: You are already delivering YR-0028…".
  /// Reading `fields` back gets the sentence without the prefix.
  String _refusalText(ApiException e) {
    final detail = e.fields?['status'];
    if (detail is List && detail.isNotEmpty) {
      final first = '${detail.first}'.trim();
      if (first.isNotEmpty) return first;
    }
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    return e.message;
  }

  /// A rider carrying a batch will hit the one-leg-at-a-time rule routinely,
  /// so it gets a dialog naming the blocking order and a way to reach it —
  /// not a snackbar that slides away before it has been read.
  Future<void> _showStartRefusal(ApiException e) async {
    final message = _refusalText(e);
    final blocked = message.toLowerCase().contains('already delivering');
    final blocker = _inTransit;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          blocked ? Icons.two_wheeler : Icons.error_outline,
          color: blocked ? _officialRouteColour : Colors.red,
          size: 30,
        ),
        title: Text(
          blocked ? "Finish your current delivery" : "Could not start",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          if (blocked && blocker != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _openDelivery(blocker);
              },
              child: Text("Open ${blocker.order.orderNumber}"),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(88, 42),
            ),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Got it"),
          ),
        ],
      ),
    );
  }

  Future<void> _openDelivery(Delivery stop) async {
    // Pushed from that order's own screen — go back to it rather than
    // stacking a second copy on top of the one already underneath.
    if (widget.focusDeliveryId == stop.id && Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(deliveryId: stop.id),
      ),
    );
    // Status very likely moved while that screen was open.
    await _silentRefresh();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // -- build -------------------------------------------------------------

  Set<Polyline> get _polylines {
    final lines = <Polyline>{};

    // The committed route is drawn whether or not its stop is selected — it
    // is the leg the rider is actually on.
    for (final stop in _stops) {
      final points = _officialRoutes[stop.id] ?? const [];
      if (points.length < 2) continue;

      lines.add(
        Polyline(
          polylineId: PolylineId('route_${stop.id}'),
          points: points,
          color: _officialRouteColour,
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    if (_previewPoints.length > 1) {
      lines.add(
        Polyline(
          polylineId: const PolylineId('osrm_preview'),
          points: _previewPoints,
          color: _previewRouteColour,
          width: 5,
          // Dashed as well as recoloured: an estimate should not look like a
          // committed route even to someone glancing at a phone on a bike.
          patterns: [PatternItem.dash(26), PatternItem.gap(14)],
          jointType: JointType.round,
        ),
      );
    }

    return lines;
  }

  /// Reads the sheet's real height back after it has been laid out.
  ///
  /// Converges in one extra frame: the first build uses the assumed height,
  /// this corrects it, and the guard stops the correction from looping.
  void _measureSheet() {
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? 0;

    if (height > 0 && (height - _sheetHeight).abs() > 1) {
      setState(() => _sheetHeight = height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    if (selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureSheet();
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text(
          "Route Map",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
            onPressed: _load,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Cached, not used to build anything — the camera maths runs from
          // async callbacks that have no constraints to hand.
          _mapHeight = constraints.maxHeight;
          return _buildMap(selected);
        },
      ),
    );
  }

  Widget _buildMap(Delivery? selected) {
    return Stack(
      children: [
        GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _stops.isEmpty
                  ? const LatLng(7.0731, 125.6128) // Davao City, as a fallback.
                  : _positionOf(_stops.first),
              zoom: RoutePath.minZoom,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _fitAllStops();
            },
            // Tapping bare map dismisses the sheet, the way a real one does.
            onTap: (_) {
              if (_selectedId != null) _closeSheet();
            },
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            // Google's own centre-on-me, top-right and clear of the zoom
            // controls at bottom-right.
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            // Keeps the SDK's controls clear of the attribution chip at the
            // top and the sheet at the bottom — measured, so a long address
            // cannot grow the sheet over the zoom buttons.
            padding: EdgeInsets.only(top: _topInset, bottom: _bottomInset),
          ),

          // ODbL attribution, required by the OSRM usage policy. Always on
          // screen, not buried behind a tap.
          const Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: _OsmAttribution(),
          ),

          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            _MapOverlay(
              icon: Icons.cloud_off,
              title: "Could not load your stops",
              message: _error!,
              onRetry: _load,
            )
          else if (_stops.isEmpty)
            _MapOverlay(
              icon: Icons.inbox_outlined,
              title: "Nothing collected yet",
              message: _unmappable.isEmpty
                  ? "Orders appear here once you mark them picked up in the "
                      "Orders tab."
                  : "You are holding ${_unmappable.length} order(s), but the "
                      "customer never pinned a location for them. Use the "
                      "written address in the Orders tab.",
              onRetry: _load,
            ),

          // A held order with no coordinates cannot be mapped. Say so, rather
          // than letting the rider count pins and come up short.
          if (!_loading && _error == null && _stops.isNotEmpty &&
              _unmappable.isNotEmpty)
            Positioned(
              top: 54,
              left: 10,
              right: 10,
              child: _UnmappableNotice(deliveries: _unmappable),
            ),

          if (selected != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _StopSheet(
                key: _sheetKey,
                delivery: selected,
                number: _numberOf(selected),
                preview: _preview,
                previewLoading: _previewLoading,
                officialRoute: _officialRoutes[selected.id] ?? const [],
                blockedBy: selected.status == 'in_transit' ? null : _inTransit,
                directionShown: _previewFor == selected.id,
                starting: _starting,
                onClose: _closeSheet,
                onDirection: () => _toggleDirection(selected),
                onStart: () => _startDelivery(selected),
                onOpen: () => _openDelivery(selected),
              ),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet
// ---------------------------------------------------------------------------

/// The tapped stop: who, where, how much to collect, and how far away it is.
class _StopSheet extends StatelessWidget {
  const _StopSheet({
    super.key,
    required this.delivery,
    required this.number,
    required this.preview,
    required this.previewLoading,
    required this.officialRoute,
    required this.blockedBy,
    required this.directionShown,
    required this.starting,
    required this.onClose,
    required this.onDirection,
    required this.onStart,
    required this.onOpen,
  });

  final Delivery delivery;
  final int number;

  /// OSRM's measurement of the drawn leg, or null when none is drawn.
  final RoutePreview? preview;
  final bool previewLoading;

  /// Whether this stop's leg is currently on the map, so the button can
  /// offer to take it away again.
  final bool directionShown;

  /// The committed route, once this leg is under way.
  final List<LatLng> officialRoute;

  /// The leg already in transit, when it is not this one. Warned about up
  /// front so the refusal is not the first the rider hears of it.
  final Delivery? blockedBy;

  final bool starting;
  final VoidCallback onClose;
  final VoidCallback onDirection;
  final VoidCallback onStart;
  final VoidCallback onOpen;

  bool get _canStart => delivery.nextStatuses.contains('in_transit');
  bool get _isUnderWay => delivery.status == 'in_transit';

  @override
  Widget build(BuildContext context) {
    final order = delivery.order;

    return Material(
      elevation: 12,
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle, purely so it reads as a sheet.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // HEADER — the pin number repeated, so the sheet and the map
              // are obviously about the same stop.
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _isUnderWay ? _officialRouteColour : _amber,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$number',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _isUnderWay ? Colors.white : _ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: GestureDetector(
                      onTap: onOpen,
                      child: Text(
                        order.orderNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ),
                  StatusBadge(status: delivery.status, compact: true),
                  IconButton(
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    tooltip: "Close",
                    onPressed: onClose,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              _row(Icons.person_outline, order.customerName),
              const SizedBox(height: 7),
              _row(Icons.location_on_outlined, order.deliveryAddress),

              const SizedBox(height: 12),

              _CollectStrip(order: order),

              const SizedBox(height: 10),

              _LegStrip(
                preview: preview,
                loading: previewLoading,
                officialRoute: officialRoute,
                etaMinutes: order.etaMinutes,
                isUnderWay: _isUnderWay,
              ),

              if (blockedBy != null && _canStart) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 17, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "You are already delivering "
                          "${blockedBy!.order.orderNumber}. Finish it before "
                          "starting this one.",
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      // Draws the leg on this map. Deliberately not a
                      // hand-off to Google Maps — turn-by-turn lives on the
                      // order's own screen, and the point of this one is to
                      // see the shape of a leg before committing to it.
                      onPressed: previewLoading ? null : onDirection,
                      icon: previewLoading
                          ? const SizedBox(
                              height: 15,
                              width: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _previewRouteColour,
                              ),
                            )
                          : Icon(
                              directionShown
                                  ? Icons.layers_clear_outlined
                                  : Icons.alt_route,
                              size: 19,
                            ),
                      label: Text(directionShown ? "Hide route" : "Route"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            directionShown ? _previewRouteColour : _ink,
                        side: BorderSide(
                          color: directionShown
                              ? _previewRouteColour
                              : Colors.grey.shade400,
                        ),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _startButton()),
                ],
              ),

              const SizedBox(height: 4),

              // The items, the notes, the customer's phone and the proof
              // upload all live on the order's own screen. This sheet is a
              // decision aid, not a replacement for it.
              TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text("Order details"),
                style: TextButton.styleFrom(
                  foregroundColor: _ink,
                  minimumSize: const Size(0, 40),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _startButton() {
    if (_isUnderWay) {
      // Nothing to start — this is the leg under way. The slot is kept so the
      // sheet does not reflow when the status changes under the rider.
      return Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _officialRouteColour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.two_wheeler, size: 18, color: _officialRouteColour),
            SizedBox(width: 7),
            Text(
              "On the way",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                color: _officialRouteColour,
              ),
            ),
          ],
        ),
      );
    }

    if (!_canStart) {
      // Unreachable while this map carries only picked_up and in_transit
      // stops, but an unfamiliar status should degrade to something inert
      // rather than a button that cannot work.
      return Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          DeliveryStatusStyle.of(delivery.status).label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13.5,
            color: Colors.grey.shade700,
          ),
        ),
      );
    }

    // Deliberately never disabled by the blocking warning above. The
    // one-leg-at-a-time rule is the server's to enforce, and a rider who
    // taps anyway deserves the server's own sentence, not a dead button.
    return ElevatedButton.icon(
      onPressed: starting ? null : onStart,
      icon: starting
          ? const SizedBox(
              height: 15,
              width: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            )
          : const Icon(Icons.play_arrow, size: 20),
      label: const Text("Start Delivery"),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: Colors.grey),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text.isEmpty ? "—" : text,
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}

/// What the rider takes at the door.
class _CollectStrip extends StatelessWidget {
  const _CollectStrip({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final collects = order.collectsCash;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: collects ? Colors.deepOrange.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            collects ? Icons.payments : Icons.check_circle,
            size: 19,
            color: collects ? Colors.deepOrange : Colors.green,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              collects ? "Collect on delivery" : "Already paid",
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          Text(
            "₱${order.amountToCollect.toStringAsFixed(2)}",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: collects ? Colors.deepOrange : Colors.green.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Distance and time for the leg from here to this stop.
class _LegStrip extends StatelessWidget {
  const _LegStrip({
    required this.preview,
    required this.loading,
    required this.officialRoute,
    required this.etaMinutes,
    required this.isUnderWay,
  });

  final RoutePreview? preview;
  final bool loading;
  final List<LatLng> officialRoute;
  final int? etaMinutes;
  final bool isUnderWay;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _shell(
        child: const Row(
          children: [
            SizedBox(
              height: 15,
              width: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: _amber),
            ),
            SizedBox(width: 11),
            Text(
              "Working out the route from where you are…",
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    final leg = preview;

    // A leg the rider just drew is measured from where they are standing
    // now, so it beats the committed numbers even on a stop under way —
    // those were fixed at the moment the delivery started.
    if (leg != null) {
      return _shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child:
                      _metric(Icons.straighten, "Distance", leg.distanceLabel),
                ),
                Container(width: 1, height: 28, color: Colors.white24),
                Expanded(
                  child: _metric(Icons.schedule, "Driving", leg.durationLabel),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              isUnderWay
                  ? "Estimate from your current position."
                  : "Estimate only — the arrival time is fixed when you start.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ],
        ),
      );
    }

    // Under way with nothing drawn: show what the backend committed.
    if (isUnderWay) {
      final km = RoutePath.distanceKm(officialRoute);
      return _shell(
        child: Row(
          children: [
            Expanded(
              child: _metric(
                Icons.straighten,
                "Distance",
                km <= 0
                    ? "—"
                    : km < 1
                        ? "${(km * 1000).round()} m"
                        : "${km.toStringAsFixed(1)} km",
              ),
            ),
            Container(width: 1, height: 28, color: Colors.white24),
            Expanded(
              child: _metric(
                Icons.schedule,
                "Arrival",
                etaMinutes == null ? "—" : "$etaMinutes min",
              ),
            ),
          ],
        ),
      );
    }

    // Nothing drawn yet. The distance comes with the route, so this says
    // which button produces it rather than showing an empty dash.
    return _shell(
      child: const Row(
        children: [
          Icon(Icons.alt_route, size: 17, color: _amber),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Tap Direction to draw the route from where you are and see how "
              "far it is.",
              style: TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(11),
      ),
      child: child,
    );
  }

  Widget _metric(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: _amber),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.white60),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

/// Required by the OSRM usage policy: the preview legs are computed from
/// OpenStreetMap data, which is ODbL-licensed and must be credited wherever
/// it is shown.
class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Text(
          "Route preview © OpenStreetMap contributors (ODbL) · OSRM",
          style: TextStyle(fontSize: 10, color: Colors.black87),
        ),
      ),
    );
  }
}

class _UnmappableNotice extends StatelessWidget {
  const _UnmappableNotice({required this.deliveries});

  final List<Delivery> deliveries;

  @override
  Widget build(BuildContext context) {
    final numbers =
        deliveries.map((d) => d.order.orderNumber).where((n) => n.isNotEmpty);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off, size: 16, color: Colors.deepOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Not on the map: ${numbers.join(', ')} — no pinned location.",
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapOverlay extends StatelessWidget {
  const _MapOverlay({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 18,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(150, 44),
              ),
              child: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }
}
