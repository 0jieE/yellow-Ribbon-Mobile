import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../controllers/cart_controller.dart';
import '../models/user_model.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/constants_service.dart';
import '../services/order_service.dart';
import '../services/payment_service.dart';
import '../services/pending_payment.dart';
import 'map_picker_screen.dart';
import 'order_detail_screen.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// Where the initial pin came from, so the screen can say so.
enum _PinSource { none, device, saved }

class CheckoutScreen extends StatefulWidget {
  final double total;

  const CheckoutScreen({super.key, required this.total});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final addressController = TextEditingController();
  final notesController = TextEditingController();

  final _auth = AuthService();
  final _orders = OrderService();
  final _payments = PaymentService();
  final _constants = ConstantsService();

  bool loading = false;
  bool loadingProfile = true;

  /// True while the device location is being resolved on open.
  bool _locating = false;

  /// Filled from GET /api/constants/ so the fee is never hardcoded here, then
  /// replaced by the delivery quote for the pinned address.
  double deliveryFee = 0;

  /// The quote for the current pin. Null until one arrives — and on a
  /// backend without per-km pricing, where the flat constants fee stands.
  DeliveryQuote? _quote;
  bool _quoting = false;

  AppUser? _user;
  AppConstants? _constantsData;
  String? _profileError;

  /// Where the customer dropped the pin. This is what gets submitted — the
  /// typed address is the landmark the rider reads, not the coordinate.
  LatLng? _pinnedLocation;
  _PinSource _pinSource = _PinSource.none;

  /// Last rejection from the server, shown inline so it survives longer than
  /// a snackbar. The geofence refusal lands here.
  String? _orderError;

  /// "cod", "gcash" and "maya" are the values `PAYMENT_TYPE` defines
  /// server-side.
  String paymentMethod = "cod";

  double get grandTotal => widget.total + deliveryFee;

  @override
  void initState() {
    super.initState();
    loadCheckoutData();
  }

  @override
  void dispose() {
    addressController.dispose();
    notesController.dispose();
    super.dispose();
  }

  // -- loading ---------------------------------------------------------

  /// Pulls the profile and the delivery fee, then resolves a starting pin.
  Future<void> loadCheckoutData() async {
    setState(() {
      loadingProfile = true;
      _profileError = null;
    });

    try {
      final results = await Future.wait([_auth.me(), _constants.fetch()]);

      final user = results[0] as AppUser;
      final constants = results[1] as AppConstants;

      if (!mounted) return;
      setState(() {
        _user = user;
        _constantsData = constants;
        deliveryFee = constants.deliveryFee;
        loadingProfile = false;
        if (addressController.text.isEmpty) {
          addressController.text = user.defaultAddress ?? '';
        }
      });

      if (_pinnedLocation == null) {
        await _resolveInitialPin(user);
      } else {
        await _refreshQuote();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        loadingProfile = false;
        _profileError = e.message;
      });
    }
  }

  /// Picks the pin to start with: the phone's current position first, falling
  /// back to the address saved on the profile.
  ///
  /// Doing this on open rather than waiting for the map picker is the point —
  /// a customer outside the delivery radius finds out here, before filling in
  /// the rest of the form and having the order refused at placement.
  Future<void> _resolveInitialPin(AppUser user) async {
    setState(() => _locating = true);

    final device = await _deviceLocation();
    if (!mounted) return;

    final saved = _savedLocationOf(user);

    setState(() {
      _locating = false;
      _pinnedLocation = device ?? saved;
      _pinSource = device != null
          ? _PinSource.device
          : (saved != null ? _PinSource.saved : _PinSource.none);
    });

    await _refreshQuote();
  }

  /// Prices delivery to the current pin.
  ///
  /// With a per-km rate the fee depends on the address, so it is re-quoted
  /// every time the pin moves. If the quote cannot be had, the flat fee from
  /// the constants stands — the server charges the right amount either way.
  Future<void> _refreshQuote() async {
    final pin = _pinnedLocation;
    final constants = _constantsData;
    if (pin == null || constants == null) return;

    setState(() => _quoting = true);
    try {
      final quote = await _orders.deliveryQuote(
        latitude: pin.latitude.toStringAsFixed(6),
        longitude: pin.longitude.toStringAsFixed(6),
      );
      if (!mounted || pin != _pinnedLocation) return;
      setState(() {
        _quote = quote;
        deliveryFee = quote.deliveryFee;
      });
    } on ApiException {
      if (!mounted || pin != _pinnedLocation) return;
      setState(() {
        _quote = null;
        deliveryFee = constants.deliveryFee;
      });
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  /// The phone's position, or null when location is off, refused, or slow.
  ///
  /// Every step is time-boxed: Android allows one runtime permission dialog
  /// at a time, and a request raised while another is on screen is dropped
  /// with no callback, which would otherwise hang checkout on open.
  Future<LatLng?> _deviceLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 20));
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 20));

      return LatLng(position.latitude, position.longitude);
    } on Exception {
      // Falling back to the saved address is fine; the customer can re-pin.
      return null;
    }
  }

  /// The coordinates stored on the customer profile, if they parse.
  LatLng? _savedLocationOf(AppUser user) {
    final lat = double.tryParse(user.defaultLatitude ?? '');
    final lng = double.tryParse(user.defaultLongitude ?? '');
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  // -- service area ----------------------------------------------------

  /// Kilometres from the service centre, or null when that cannot be worked
  /// out yet.
  double? get _distanceFromCentreKm {
    final pin = _pinnedLocation;
    final constants = _constantsData;
    if (pin == null || constants == null) return null;

    return haversineKm(
      constants.serviceAreaCenterLat,
      constants.serviceAreaCenterLng,
      pin.latitude,
      pin.longitude,
    );
  }

  /// Whether the pin is deliverable. Null while unknown.
  ///
  /// Same formula and same constants the backend geofences with, so this
  /// agrees with the check `POST /api/orders/` runs — the server is still the
  /// authority, this only saves a doomed round trip.
  bool? get _pinInZone {
    final distance = _distanceFromCentreKm;
    final radius = _constantsData?.serviceAreaRadiusKm;
    if (distance == null || radius == null || radius <= 0) return null;
    return distance <= radius;
  }

  // -- actions ---------------------------------------------------------

  Future<void> openMapPicker() async {
    final constants = _constantsData;
    if (constants == null) {
      _snack("The delivery area has not loaded yet.");
      return;
    }

    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          constants: constants,
          initialLocation: _pinnedLocation,
        ),
      ),
    );

    if (picked == null || !mounted) return;
    setState(() {
      _pinnedLocation = picked;
      _pinSource = _PinSource.none;
      // A new pin invalidates a previous out-of-area rejection.
      _orderError = null;
    });
    await _refreshQuote();
  }

  Future<void> placeOrder() async {
    final user = _user;

    if (user == null) {
      _snack("Your profile has not loaded yet.");
      return;
    }

    if (CartController.cart.isEmpty) {
      _snack("Your cart is empty.");
      return;
    }

    if (addressController.text.trim().isEmpty) {
      _snack("Please enter delivery address");
      return;
    }

    // POST /api/orders/ geofences these coordinates before creating anything,
    // so the order cannot be placed until the customer has dropped a pin.
    final pinned = _pinnedLocation;
    if (pinned == null) {
      _snack("Please pin your delivery location on the map.");
      return;
    }

    setState(() {
      loading = true;
      _orderError = null;
    });

    try {
      final order = await _orders.placeOrder(
        items: CartController.cart,
        deliveryAddress: addressController.text.trim(),
        // delivery_latitude/longitude are DecimalField(max_digits=9,
        // decimal_places=6) — send exactly six places so the server never has
        // to round a value it was given.
        latitude: pinned.latitude.toStringAsFixed(6),
        longitude: pinned.longitude.toStringAsFixed(6),
        paymentType: paymentMethod,
        deliveryNotes: notesController.text.trim(),
      );

      // A GCash or Maya order is created as `pending_payment` and must not
      // reach the kitchen until the gateway confirms the money. Send the
      // customer to the hosted checkout page; they return over the
      // yellowribbon:// deep link.
      if (order.awaitingPayment) {
        // Recorded before leaving for the browser: the return deep link
        // carries no order id, so this is how the app knows what came back.
        await PendingPayment.instance.remember(order.id);

        final session = await _payments.startCheckout(order.id);
        final launched = await launchUrl(
          Uri.parse(session.checkoutUrl),
          mode: LaunchMode.externalApplication,
        );

        if (!mounted) return;

        // The cart is cleared either way: the order exists server-side now.
        CartController.clearCart();
        setState(() => loading = false);

        _openOrder(
          order.id,
          launched
              ? "${order.orderNumber} placed. Complete the "
                  "${order.paymentMethodLabel} payment."
              : "${order.orderNumber} is waiting for payment but the "
                  "${order.paymentMethodLabel} page could not be opened.",
        );
        return;
      }

      CartController.clearCart();

      if (!mounted) return;
      setState(() => loading = false);
      _openOrder(order.id, "Order ${order.orderNumber} placed successfully!");
    } on ApiException catch (e) {
      if (!mounted) return;
      // Covers the out-of-service-area rejection, an unavailable menu item,
      // and any other server-side validation. The customer stays on checkout
      // with the cart intact so they can re-pin or change the order, and the
      // message is held inline rather than vanishing with a snackbar.
      setState(() {
        loading = false;
        _orderError = e.message;
      });
      _snack(e.message);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Leaves checkout on the new order's detail screen rather than dropping
  /// the customer back on the menu with no sign of what just happened.
  ///
  /// Replaces checkout and the cart in the stack, so backing out of the
  /// order returns to the menu and not to a cart that has been emptied.
  void _openOrder(int orderId, String message) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)),
      // Keep the shell underneath; drop cart and checkout.
      (route) => route.isFirst,
    );
    _snack(message);
  }

  // -- build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text(
          "Checkout",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: _amber,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: loadingProfile
          ? const Center(child: CircularProgressIndicator())
          : _profileError != null
              ? _ErrorState(message: _profileError!, onRetry: loadCheckoutData)
              : _buildForm(),
      bottomNavigationBar: loadingProfile || _profileError != null
          ? null
          : _buildFooter(),
    );
  }

  Widget _buildForm() {
    final user = _user!;
    final outOfZone = _pinInZone == false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // OUT OF RANGE — first thing on the screen, before the form.
        if (outOfZone) ...[
          _OutOfZoneWarning(
            distanceKm: _distanceFromCentreKm!,
            radiusKm: _constantsData!.serviceAreaRadiusKm,
            city: _constantsData!.serviceAreaCity,
            onChange: openMapPicker,
          ),
          const SizedBox(height: 14),
        ],

        _Section(
          title: "Customer",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _line(Icons.person_outline, user.displayName),
              const SizedBox(height: 8),
              _line(
                Icons.phone_outlined,
                user.phone.isEmpty ? "No phone number" : user.phone,
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        _Section(
          title: "Delivery address",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: addressController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: "House number, street, landmark",
                  helperText: "What the rider reads to find your door",
                  filled: true,
                  fillColor: const Color(0xFFF6F6F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 14),

              _LocationPin(
                location: _pinnedLocation,
                source: _pinSource,
                locating: _locating,
                inZone: _pinInZone,
                onPressed: openMapPicker,
              ),

              const SizedBox(height: 12),

              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: "Delivery notes (optional)",
                  filled: true,
                  fillColor: const Color(0xFFF6F6F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        _Section(
          title: "Payment",
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: RadioGroup<String>(
            groupValue: paymentMethod,
            onChanged: (value) =>
                setState(() => paymentMethod = value ?? "cod"),
            child: Column(
              children: const [
                RadioListTile<String>(
                  value: "cod",
                  activeColor: _ink,
                  contentPadding: EdgeInsets.zero,
                  title: Text("Cash on Delivery"),
                ),
                RadioListTile<String>(
                  value: "gcash",
                  activeColor: _ink,
                  contentPadding: EdgeInsets.zero,
                  title: Text("GCash"),
                ),
                RadioListTile<String>(
                  value: "maya",
                  activeColor: _ink,
                  contentPadding: EdgeInsets.zero,
                  title: Text("Maya Wallet"),
                  subtitle: Text(
                    "Log in to your Maya wallet to pay, then return to the app",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // SUMMARY — an estimate. The server recomputes every figure from its
        // own prices when the order is created.
        _Section(
          title: "Summary",
          child: Column(
            children: [
              _row("Subtotal", widget.total),
              const SizedBox(height: 6),
              _row(
                _quoting
                    ? "Delivery fee (calculating…)"
                    : (_quote?.isPerKm ?? false)
                        ? "Delivery fee (${_quote!.distanceKm.toStringAsFixed(1)} km)"
                        : "Delivery fee",
                deliveryFee,
              ),
              const Divider(height: 22),
              _row("Total", grandTotal, isBold: true),
            ],
          ),
        ),

        // SERVER REJECTION — most often the geofence refusing an address
        // outside the delivery radius.
        if (_orderError != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _orderError!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: openMapPicker,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text("Change delivery location"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    final outOfZone = _pinInZone == false;
    final blocked = loading || outOfZone;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total", style: TextStyle(fontSize: 15)),
                  Text(
                    "₱${grandTotal.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: _amber,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: blocked ? null : placeOrder,
                  child: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          outOfZone
                              ? "OUTSIDE DELIVERY AREA"
                              : paymentMethod != "cod"
                                  ? "PLACE ORDER & PAY"
                                  : "PLACE ORDER",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 0.8,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }

  Widget _row(String label, double value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 16 : 14,
          ),
        ),
        Text(
          "₱${value.toStringAsFixed(2)}",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isBold ? 18 : 14,
            color: isBold ? Colors.deepOrange : Colors.black,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// A white card with a titled header, matching the rest of the app.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
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
                title.toUpperCase(),
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

/// Shown as soon as checkout opens if the starting pin is out of range, so
/// the customer is not left to discover it after filling the form in.
class _OutOfZoneWarning extends StatelessWidget {
  const _OutOfZoneWarning({
    required this.distanceKm,
    required this.radiusKm,
    required this.city,
    required this.onChange,
  });

  final double distanceKm;
  final double radiusKm;
  final String city;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wrong_location, color: Colors.red, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Outside the delivery area",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "We deliver within ${radiusKm.toStringAsFixed(0)} km of $city. "
            "This location is about ${distanceKm.toStringAsFixed(1)} km away, "
            "so the order cannot be placed.",
            style: TextStyle(color: Colors.red.shade900, height: 1.45),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onChange,
              icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
              label: const Text("Pin a different location"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade900,
                side: BorderSide(color: Colors.red.shade300),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The map pin control, and where the current pin came from.
class _LocationPin extends StatelessWidget {
  const _LocationPin({
    required this.location,
    required this.source,
    required this.locating,
    required this.inZone,
    required this.onPressed,
  });

  final LatLng? location;
  final _PinSource source;
  final bool locating;
  final bool? inZone;
  final VoidCallback onPressed;

  String get _sourceNote {
    switch (source) {
      case _PinSource.device:
        return "Using your current location";
      case _PinSource.saved:
        return "Using your saved address";
      case _PinSource.none:
        return "Pinned on the map";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (locating) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text("Finding your location…"),
          ],
        ),
      );
    }

    final pinned = location;

    if (pinned == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text("Pin delivery location"),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Required — we check it is inside the delivery area.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      );
    }

    final bad = inZone == false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bad ? Colors.red.shade50 : _ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            bad ? Icons.wrong_location : Icons.place,
            color: bad ? Colors.red : _amber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sourceNote,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: bad ? Colors.red.shade900 : Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${pinned.latitude.toStringAsFixed(6)}, "
                  "${pinned.longitude.toStringAsFixed(6)}",
                  style: TextStyle(
                    fontSize: 11.5,
                    color: bad ? Colors.red.shade700 : Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: bad ? Colors.red.shade900 : _amber,
            ),
            child: const Text("Change"),
          ),
        ],
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
