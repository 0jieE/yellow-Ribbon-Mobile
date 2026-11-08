import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme.dart';

/// What the store-location picker hands back.
class StoreLocation {
  const StoreLocation(this.position, this.radiusKm);

  final LatLng position;
  final double radiusKm;
}

/// Pick the store's position and the delivery radius on a map.
///
/// The store is the centre of the delivery area, so this is both "where is
/// the shop" and "how far do we deliver". Nobody knows their latitude by
/// heart; standing in the shop and tapping "Use my location" is the usual
/// way to set it.
class StoreLocationScreen extends StatefulWidget {
  const StoreLocationScreen({
    super.key,
    required this.initial,
    required this.initialRadiusKm,
  });

  final LatLng initial;
  final double initialRadiusKm;

  @override
  State<StoreLocationScreen> createState() => _StoreLocationScreenState();
}

/// The slider's range. The server accepts 0.1 to 100 km; a delivery shop
/// rarely goes past 30, and a larger saved value widens the slider to fit.
const _minRadiusKm = 0.5;
const _sliderMaxKm = 30.0;

class _StoreLocationScreenState extends State<StoreLocationScreen> {
  GoogleMapController? _controller;

  late LatLng _pin = widget.initial;
  late double _radiusKm =
      widget.initialRadiusKm.clamp(_minRadiusKm, double.infinity);
  bool _locating = false;

  double get _maxKm => math.max(_sliderMaxKm, widget.initialRadiusKm);

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _movePin(LatLng position) => setState(() => _pin = position);

  /// Frames the whole delivery circle.
  Future<void> _fitCircle() async {
    final controller = _controller;
    if (controller == null) return;

    // Degrees per km: latitude is constant, longitude shrinks with cos(lat).
    final dLat = _radiusKm / 110.574;
    final dLng =
        _radiusKm / (111.320 * math.cos(_pin.latitude * math.pi / 180));

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(_pin.latitude - dLat, _pin.longitude - dLng),
            northeast: LatLng(_pin.latitude + dLat, _pin.longitude + dLng),
          ),
          40,
        ),
      );
    } on Exception {
      // The map can refuse a bounds move before it has laid out.
      await controller.animateCamera(CameraUpdate.newLatLngZoom(_pin, 12));
    }
  }

  /// Moves the store pin to where the phone is — the admin standing in the
  /// shop is the common case.
  Future<void> _useMyLocation() async {
    setState(() => _locating = true);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _notify("Location is turned off on this phone.");
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _notify("Location permission was denied. Tap the map to place the "
            "store instead.");
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() => _pin = LatLng(position.latitude, position.longitude));
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(_pin, 16));
      _notify("Store pinned at your location.");
    } on Exception {
      _notify("Could not get your current location.");
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Store location")),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _pin, zoom: 12),
            onMapCreated: (controller) {
              _controller = controller;
              _fitCircle();
            },
            onTap: _movePin,
            markers: {
              Marker(
                markerId: const MarkerId('store'),
                position: _pin,
                draggable: true,
                onDragEnd: _movePin,
                infoWindow: const InfoWindow(title: 'Store'),
              ),
            },
            circles: {
              Circle(
                circleId: const CircleId('delivery_area'),
                center: _pin,
                radius: _radiusKm * 1000,
                fillColor: kAmber.withValues(alpha: 0.15),
                strokeColor: kAmber,
                strokeWidth: 2,
              ),
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            // Keeps the native zoom controls above the bottom card.
            padding: const EdgeInsets.only(bottom: 250),
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: FloatingActionButton.extended(
                    heroTag: 'store_use_my_location',
                    onPressed: _locating ? null : _useMyLocation,
                    backgroundColor: Colors.white,
                    foregroundColor: kInk,
                    icon: _locating
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: const Text("Use my location"),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          "Tap the map or drag the pin to where the store is.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: kMuted),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.radar, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              "Delivery radius",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            Text(
                              "${_radiusKm.toStringAsFixed(1)} km",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _radiusKm.clamp(_minRadiusKm, _maxKm),
                          min: _minRadiusKm,
                          max: _maxKm,
                          // Half-kilometre steps.
                          divisions: ((_maxKm - _minRadiusKm) * 2).round(),
                          activeColor: kInk,
                          label: "${_radiusKm.toStringAsFixed(1)} km",
                          onChanged: (value) =>
                              setState(() => _radiusKm = value),
                          onChangeEnd: (_) => _fitCircle(),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          onPressed: () => Navigator.pop(
                            context,
                            StoreLocation(_pin, _radiusKm),
                          ),
                          child: const Text("Use this location"),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
