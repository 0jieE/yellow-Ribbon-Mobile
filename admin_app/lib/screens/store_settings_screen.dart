import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/store_settings.dart';
import '../services/api_client.dart';
import '../services/store_settings_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/order_status.dart';
import '../widgets/section_card.dart';
import 'store_location_screen.dart';

/// The delivery fee, service area and gateway fee rates.
///
/// Saved values apply to the next order placed and the next time the
/// customer app opens checkout. Existing orders keep the fee they were
/// placed with.
class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

/// One editable value: its JSON key, the form label, and the server's limits.
class _Field {
  const _Field(
    this.key,
    this.label, {
    required this.icon,
    this.min,
    this.max,
    this.helper,
    this.prefix,
    this.suffix,
    this.numeric = true,
  });

  final String key;
  final String label;
  final IconData icon;
  final double? min;
  final double? max;
  final String? helper;
  final String? prefix;
  final String? suffix;
  final bool numeric;
}

// Limits mirror the backend's validators so most mistakes are caught before
// the round trip; the server still has the final say.
const _deliveryFields = [
  _Field('delivery_fee', 'Delivery fee',
      icon: Icons.delivery_dining, min: 0, max: 10000, prefix: '₱ ',
      helper: 'Flat fee, or the base fee when a per-km rate is set.'),
  _Field('delivery_fee_per_km', 'Extra per km',
      icon: Icons.add_road, min: 0, max: 1000, prefix: '₱ ', suffix: '/ km',
      helper: 'Leave at 0 for a flat fee everywhere in the service area.'),
];

const _areaFields = [
  _Field('service_area_city', 'City / area name',
      icon: Icons.location_city, numeric: false),
];

/// Set on the map, not typed — nobody knows their store's latitude. They
/// still have controllers so a save sends only what changed.
const _mapKeys = [
  'service_area_center_lat',
  'service_area_center_lng',
  'service_area_radius_km',
];

const _gatewayFields = [
  _Field('paymongo_fee_percent', 'GCash fee',
      icon: Icons.percent, min: 0, max: 100, suffix: '%'),
  _Field('paymongo_fee_fixed', 'GCash fixed fee',
      icon: Icons.payments_outlined, min: 0, max: 10000, prefix: '₱ '),
  _Field('maya_fee_percent', 'Maya fee',
      icon: Icons.percent, min: 0, max: 100, suffix: '%'),
  _Field('maya_fee_fixed', 'Maya fixed fee',
      icon: Icons.payments_outlined, min: 0, max: 10000, prefix: '₱ '),
];

const _allFields = [..._deliveryFields, ..._areaFields, ..._gatewayFields];

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = StoreSettingsService();

  final _controllers = {
    for (final key in [..._allFields.map((f) => f.key), ..._mapKeys])
      key: TextEditingController(),
  };

  StoreSettings? _settings;

  /// What the server last returned, keyed like the controllers, so a save
  /// sends only the values that actually changed.
  Map<String, String> _saved = const {};

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _saveError;
  Map<String, dynamic> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    _load();
    // The fee example under the delivery card follows what is typed.
    _controllers['delivery_fee']!.addListener(_rebuild);
    _controllers['delivery_fee_per_km']!.addListener(_rebuild);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      _apply(await _service.fetch());
      if (mounted) setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  void _apply(StoreSettings settings) {
    final values = {
      'delivery_fee': settings.deliveryFee,
      'delivery_fee_per_km': settings.deliveryFeePerKm,
      'service_area_city': settings.serviceAreaCity,
      'service_area_center_lat': settings.serviceAreaCenterLat,
      'service_area_center_lng': settings.serviceAreaCenterLng,
      'service_area_radius_km': settings.serviceAreaRadiusKm,
      'paymongo_fee_percent': settings.paymongoFeePercent,
      'paymongo_fee_fixed': settings.paymongoFeeFixed,
      'maya_fee_percent': settings.mayaFeePercent,
      'maya_fee_fixed': settings.mayaFeeFixed,
    };
    for (final entry in values.entries) {
      _controllers[entry.key]!.text = entry.value;
    }
    _settings = settings;
    _saved = values;
  }

  Map<String, String> get _changes => {
        for (final entry in _controllers.entries)
          if (entry.value.text.trim() != _saved[entry.key])
            entry.key: entry.value.text.trim(),
      };

  Future<void> _save() async {
    setState(() => _fieldErrors = const {});
    if (!_formKey.currentState!.validate()) return;

    final changes = _changes;
    if (changes.isEmpty) {
      _snack("Nothing has changed.");
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final updated = await _service.update(changes);
      if (!mounted) return;
      setState(() {
        _apply(updated);
        _saving = false;
      });
      _snack("Saved. New orders use these settings from now on.");
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.message;
        _fieldErrors = e.fields ?? const {};
      });
      // Re-run validation so the server's field errors render inline.
      _formKey.currentState!.validate();
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  LatLng? get _mapCentre {
    final lat = double.tryParse(_controllers['service_area_center_lat']!.text);
    final lng = double.tryParse(_controllers['service_area_center_lng']!.text);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  double get _mapRadiusKm =>
      double.tryParse(_controllers['service_area_radius_km']!.text) ?? 0;

  /// A server rejection of any map-set value, shown under the preview since
  /// those values have no text box of their own.
  String? get _mapError {
    for (final key in _mapKeys) {
      final error = _serverErrorFor(key);
      if (error != null) return error;
    }
    return null;
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.push<StoreLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => StoreLocationScreen(
          // Falls back to Kidapawan City if nothing parses.
          initial: _mapCentre ?? const LatLng(7.0083, 125.0894),
          initialRadiusKm: _mapRadiusKm > 0 ? _mapRadiusKm : 8,
        ),
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      // The server stores six decimal places for the centre and two for the
      // radius; send exactly that so nothing is rounded behind the admin.
      _controllers['service_area_center_lat']!.text =
          picked.position.latitude.toStringAsFixed(6);
      _controllers['service_area_center_lng']!.text =
          picked.position.longitude.toStringAsFixed(6);
      _controllers['service_area_radius_km']!.text =
          picked.radiusKm.toStringAsFixed(2);
      _fieldErrors = {
        for (final entry in _fieldErrors.entries)
          if (!_mapKeys.contains(entry.key)) entry.key: entry.value,
      };
    });
    _snack("Location set. Tap Save settings to apply it.");
  }

  String? _serverErrorFor(String key) {
    final value = _fieldErrors[key];
    if (value is List && value.isNotEmpty) return '${value.first}';
    if (value is String) return value;
    return null;
  }

  String? _validate(_Field field, String? raw) {
    final server = _serverErrorFor(field.key);
    if (server != null) return server;

    final text = raw?.trim() ?? '';
    if (text.isEmpty) return "Required";
    if (!field.numeric) return null;

    final value = double.tryParse(text);
    if (value == null) return "Enter a number";
    if (field.min != null && value < field.min!) {
      return "Must be at least ${_plain(field.min!)}";
    }
    if (field.max != null && value > field.max!) {
      return "Must be at most ${_plain(field.max!)}";
    }
    return null;
  }

  static String _plain(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Store settings")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? EmptyState(
                  icon: Icons.cloud_off,
                  title: "Couldn't load the settings",
                  message: _loadError!,
                  onRetry: _load,
                )
              : _buildForm(),
    );
  }

  Widget _buildForm() {
    final updatedAt = _settings?.updatedAt;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          SectionCard(
            title: "Delivery fee",
            icon: Icons.delivery_dining,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._fieldsFor(_deliveryFields),
                _FeeExample(
                  base: double.tryParse(_controllers['delivery_fee']!.text),
                  perKm: double.tryParse(
                    _controllers['delivery_fee_per_km']!.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: "Service area",
            icon: Icons.map_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._fieldsFor(_areaFields),
                _AreaPreview(
                  centre: _mapCentre,
                  radiusKm: _mapRadiusKm,
                  error: _mapError,
                  onChange: _pickOnMap,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: "Payment gateway fees",
            icon: Icons.account_balance_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "What each gateway keeps from an online payment. Used to "
                  "show what actually reaches the store in reports. Set these "
                  "to the rates in the store's gateway contract.",
                  style: TextStyle(fontSize: 12, color: kMuted),
                ),
                const SizedBox(height: 14),
                ..._fieldsFor(_gatewayFields),
              ],
            ),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828).withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _saveError!,
                style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 12.5),
              ),
            ),
          ],
          const SizedBox(height: 22),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
                  )
                : const Icon(Icons.save_outlined, size: 20),
            label: const Text("Save settings"),
          ),
          if (updatedAt != null) ...[
            const SizedBox(height: 12),
            Text(
              "Last changed ${Dates.full(updatedAt)}",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _fieldsFor(List<_Field> fields) => [
        for (final field in fields) ...[
          TextFormField(
            controller: _controllers[field.key],
            keyboardType: field.numeric
                ? const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  )
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: field.label,
              prefixIcon: Icon(field.icon),
              prefixText: field.prefix,
              suffixText: field.suffix,
              helperText: field.helper,
              helperMaxLines: 2,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            ),
            validator: (value) => _validate(field, value),
          ),
          const SizedBox(height: 14),
        ],
      ];
}

/// The store and its delivery circle, as a small non-interactive map, with
/// the button that opens the full picker.
class _AreaPreview extends StatelessWidget {
  const _AreaPreview({
    required this.centre,
    required this.radiusKm,
    required this.error,
    required this.onChange,
  });

  final LatLng? centre;
  final double radiusKm;
  final String? error;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final centre = this.centre;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (centre != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 170,
              child: GoogleMap(
                // Rebuilt when the location changes, so the static preview
                // shows the new spot rather than the first one.
                key: ValueKey('$centre/$radiusKm'),
                liteModeEnabled: true,
                initialCameraPosition: CameraPosition(
                  target: centre,
                  zoom: _zoomFor(radiusKm),
                ),
                markers: {
                  Marker(markerId: const MarkerId('store'), position: centre),
                },
                circles: {
                  Circle(
                    circleId: const CircleId('delivery_area'),
                    center: centre,
                    radius: radiusKm * 1000,
                    fillColor: kAmber.withValues(alpha: 0.15),
                    strokeColor: kAmber,
                    strokeWidth: 2,
                  ),
                },
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Text(
          "Delivers within ${radiusKm.toStringAsFixed(1)} km of the store.",
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(fontSize: 12, color: Color(0xFFC62828)),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onChange,
          icon: const Icon(Icons.map_outlined, size: 19),
          label: const Text("Set store location on map"),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// A zoom that fits the circle in the preview, roughly.
  static double _zoomFor(double radiusKm) {
    if (radiusKm <= 1) return 13.5;
    if (radiusKm <= 3) return 12;
    if (radiusKm <= 6) return 11;
    if (radiusKm <= 12) return 10;
    if (radiusKm <= 25) return 9;
    return 8;
  }
}

/// "An address 5 km away pays ₱X" — so the admin sees what a per-km rate
/// means before saving it.
class _FeeExample extends StatelessWidget {
  const _FeeExample({required this.base, required this.perKm});

  final double? base;
  final double? perKm;

  @override
  Widget build(BuildContext context) {
    final base = this.base;
    final perKm = this.perKm;
    if (base == null || perKm == null) return const SizedBox.shrink();

    final text = perKm == 0
        ? "Every address in the service area pays ₱${base.toStringAsFixed(2)}."
        : "An address 3 km from the store pays "
            "₱${(base + 3 * perKm).toStringAsFixed(2)}; 5 km pays "
            "₱${(base + 5 * perKm).toStringAsFixed(2)} (straight-line distance).";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: kAmber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5)),
    );
  }
}
