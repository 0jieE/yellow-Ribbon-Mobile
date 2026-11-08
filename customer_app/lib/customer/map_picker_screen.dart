import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/constants_service.dart';
import '../utils/route_path.dart';

/// Great-circle distance in kilometres.
///
/// Deliberately the same formula and Earth radius as `core/geofence.py`, so
/// the in-zone hint shown here agrees with the check the server actually
/// runs. The server remains the authority — this only saves the customer a
/// round trip to discover they are out of range.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0088;

  double toRadians(double degrees) => degrees * math.pi / 180.0;

  final phi1 = toRadians(lat1);
  final phi2 = toRadians(lat2);
  final dPhi = toRadians(lat2 - lat1);
  final dLambda = toRadians(lng2 - lng1);

  final a = math.pow(math.sin(dPhi / 2), 2) +
      math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);

  return 2 * earthRadiusKm * math.asin(math.sqrt(a));
}

/// Full-screen picker for the delivery point.
///
/// Opens centred on the service area, draws its radius, and returns the
/// marker position — never the device position — when confirmed.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({
    super.key,
    required this.constants,
    this.initialLocation,
  });

  final AppConstants constants;

  /// Where to drop the marker on open. Falls back to the service centre.
  final LatLng? initialLocation;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _controller;

  late LatLng _pinned;
  bool _locating = false;

  LatLng get _serviceCentre => LatLng(
        widget.constants.serviceAreaCenterLat,
        widget.constants.serviceAreaCenterLng,
      );

  @override
  void initState() {
    super.initState();
    _pinned = widget.initialLocation ?? _serviceCentre;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  double get _distanceKm => haversineKm(
        widget.constants.serviceAreaCenterLat,
        widget.constants.serviceAreaCenterLng,
        _pinned.latitude,
        _pinned.longitude,
      );

  bool get _inZone => _distanceKm <= widget.constants.serviceAreaRadiusKm;

  void _movePin(LatLng position) => setState(() => _pinned = position);

  /// Centres the camera on the device. The marker deliberately stays where
  /// the customer put it — being near a place is not the same as wanting
  /// delivery there, so the pin is never moved on their behalf.
  Future<void> _centreOnMe() async {
    setState(() => _locating = true);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _notify("Location services are turned off on this device.");
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _notify("Location permission was denied.");
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _notify(
          "Location permission is permanently denied. Enable it in Settings, "
          "or just drag the pin instead.",
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          RoutePath.minZoom,
        ),
      );

      if (!mounted) return;
      _notify("Centred on your location. Drag the pin to set the drop-off.");
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
    const primaryYellow = Color(0xFFFFC107);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pin delivery location"),
        backgroundColor: primaryYellow,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _pinned,
              // Close enough to pick out a specific building.
              zoom: RoutePath.minZoom,
            ),
            onMapCreated: (controller) => _controller = controller,
            // Tap anywhere to move the pin — easier than dragging on a
            // small screen.
            onTap: _movePin,
            markers: {
              Marker(
                markerId: const MarkerId('delivery'),
                position: _pinned,
                draggable: true,
                onDragEnd: _movePin,
                infoWindow: const InfoWindow(title: 'Deliver here'),
              ),
            },
            circles: {
              Circle(
                circleId: const CircleId('service_area'),
                center: _serviceCentre,
                radius: widget.constants.serviceAreaRadiusKm * 1000,
                fillColor: primaryYellow.withValues(alpha: 0.12),
                strokeColor: primaryYellow,
                strokeWidth: 2,
              ),
            },
            // The blue dot is useful context, but it is not the submitted
            // point. Flutter shows it only once permission is granted.
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            // Keeps the native zoom controls above the confirm card and the
            // banner, instead of behind them where they cannot be tapped.
            padding: const EdgeInsets.only(top: 70, bottom: 210),
          ),

          // ZONE STATUS
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _ZoneBanner(
              inZone: _inZone,
              distanceKm: _distanceKm,
              city: widget.constants.serviceAreaCity,
              radiusKm: widget.constants.serviceAreaRadiusKm,
            ),
          ),

          // CONTROLS
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
                    heroTag: 'centre_on_me',
                    onPressed: _locating ? null : _centreOnMe,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    icon: _locating
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: const Text("Centre on my location"),
                  ),
                ),

                const SizedBox(height: 12),

                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          "Pinned: ${_pinned.latitude.toStringAsFixed(6)}, "
                          "${_pinned.longitude.toStringAsFixed(6)}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Tap the map or drag the pin to adjust.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryYellow,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.all(14),
                          ),
                          // Confirming out-of-zone is allowed: the server
                          // makes the final call and its message is the one
                          // the customer should act on.
                          onPressed: () => Navigator.pop(context, _pinned),
                          child: const Text(
                            "Confirm location",
                            style: TextStyle(fontWeight: FontWeight.bold),
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
      ),
    );
  }
}

class _ZoneBanner extends StatelessWidget {
  const _ZoneBanner({
    required this.inZone,
    required this.distanceKm,
    required this.city,
    required this.radiusKm,
  });

  final bool inZone;
  final double distanceKm;
  final String city;
  final double radiusKm;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: inZone ? Colors.green.shade50 : Colors.red.shade50,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              inZone ? Icons.check_circle : Icons.error_outline,
              color: inZone ? Colors.green : Colors.red,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                inZone
                    ? "Inside the delivery area "
                        "(${distanceKm.toStringAsFixed(1)} km from the centre)."
                    : "Outside the delivery area. We deliver within "
                        "${radiusKm.toStringAsFixed(0)} km of $city — this pin "
                        "is ${distanceKm.toStringAsFixed(1)} km away.",
                style: TextStyle(
                  fontSize: 12,
                  color: inZone ? Colors.green.shade900 : Colors.red.shade900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
