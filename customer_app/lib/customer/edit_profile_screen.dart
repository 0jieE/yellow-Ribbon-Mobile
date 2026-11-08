import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../models/user_model.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/constants_service.dart';
import 'map_picker_screen.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// `PATCH /api/auth/me/`.
///
/// Covers exactly what `MeSerializer` will accept: name, phone, and
/// the saved delivery address with its coordinates. `username` is read-only
/// server-side, so it is shown but not editable.
///
/// Pops with `true` when something was saved.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  final _constants = ConstantsService();

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _address;

  LatLng? _location;

  bool _saving = false;
  String? _error;

  /// Field errors from the serializer, keyed by field name.
  Map<String, dynamic> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    final user = widget.user;

    _firstName = TextEditingController(text: user.firstName);
    _lastName = TextEditingController(text: user.lastName);
    _phone = TextEditingController(text: user.phone);
    _address = TextEditingController(text: user.defaultAddress ?? '');

    final lat = double.tryParse(user.defaultLatitude ?? '');
    final lng = double.tryParse(user.defaultLongitude ?? '');
    if (lat != null && lng != null) _location = LatLng(lat, lng);
  }

  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _lastName,
      _phone,
      _address,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _serverErrorFor(String field) {
    final value = _fieldErrors[field];
    if (value is List && value.isNotEmpty) return '${value.first}';
    if (value is String) return value;
    return null;
  }

  Future<void> _pickLocation() async {
    try {
      final constants = await _constants.fetch();
      if (!mounted) return;

      final picked = await Navigator.push<LatLng>(
        context,
        MaterialPageRoute(
          builder: (_) => MapPickerScreen(
            constants: constants,
            initialLocation: _location,
          ),
        ),
      );

      if (picked == null || !mounted) return;
      setState(() => _location = picked);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    try {
      await _auth.updateProfile(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim(),
        defaultAddress: _address.text.trim(),
        // Six decimal places, matching the DecimalField the server stores
        // these in.
        defaultLatitude: _location?.latitude.toStringAsFixed(6),
        defaultLongitude: _location?.longitude.toStringAsFixed(6),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
        _fieldErrors = e.fields ?? const {};
      });
      // Re-run validation so the server's field errors render inline.
      _formKey.currentState!.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        title: const Text(
          "Edit Profile",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: _amber,
        foregroundColor: Colors.black,
        elevation: 0,
      ),

      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _Section(
              title: "Your details",
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstName,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoration("First name"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lastName,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoration("Last name"),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: _decoration(
                      "Phone",
                      error: _serverErrorFor('phone'),
                      helper: "Riders use this to reach you",
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            _Section(
              title: "Default delivery location",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Used to prefill checkout. Saving a location here means "
                    "you do not have to pin one every time you order.",
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _address,
                    maxLines: 2,
                    decoration: _decoration(
                      "Address",
                      hint: "House number, street, landmark",
                    ),
                  ),

                  const SizedBox(height: 14),

                  _LocationRow(
                    location: _location,
                    onPressed: _pickLocation,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            _Section(
              title: "Account",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: widget.user.username,
                    enabled: false,
                    decoration: _decoration(
                      "Username",
                      helper: "Your username cannot be changed",
                    ),
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            ],
          ],
        ),
      ),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ink,
                  foregroundColor: _amber,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _amber,
                        ),
                      )
                    : const Icon(Icons.check),
                label: const Text(
                  "SAVE CHANGES",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(
    String label, {
    String? hint,
    String? error,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      helperText: helper,
      filled: true,
      fillColor: const Color(0xFFF6F6F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}

/// The saved map pin, or an invitation to set one.
class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.location, required this.onPressed});

  final LatLng? location;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final pinned = location;

    if (pinned == null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text("Set location on map"),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(14),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.place, color: _amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Location saved",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${pinned.latitude.toStringAsFixed(6)}, "
                  "${pinned.longitude.toStringAsFixed(6)}",
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(foregroundColor: _amber),
            child: const Text("Change"),
          ),
        ],
      ),
    );
  }
}

/// White card with the amber-accented header used across the app.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
