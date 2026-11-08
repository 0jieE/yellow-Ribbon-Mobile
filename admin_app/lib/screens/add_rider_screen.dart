import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/rider_admin_service.dart';
import '../theme.dart';

/// `POST /api/admin/riders/` — the only way a rider account is created.
///
/// Riders cannot self-register, and `/api/auth/register/` makes customers
/// only, so every field the serializer accepts is offered here. `username`,
/// and `password` are required; the rest populate the rider profile.
class AddRiderScreen extends StatefulWidget {
  const AddRiderScreen({super.key});

  @override
  State<AddRiderScreen> createState() => _AddRiderScreenState();
}

class _AddRiderScreenState extends State<AddRiderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _riders = RiderAdminService();

  final username = TextEditingController();
  final password = TextEditingController();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final phone = TextEditingController();
  final vehicleType = TextEditingController();
  final plateNumber = TextEditingController();

  bool _saving = false;
  bool _obscure = true;
  String? _error;

  /// Field-level errors from the serializer, keyed by field name — a taken
  /// username or a password Django's validators rejected.
  Map<String, dynamic> _fieldErrors = const {};

  @override
  void dispose() {
    for (final controller in [
      username,
      password,
      firstName,
      lastName,
      phone,
      vehicleType,
      plateNumber,
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    try {
      final rider = await _riders.create(
        username: username.text.trim(),
        password: password.text,
        firstName: firstName.text.trim(),
        lastName: lastName.text.trim(),
        phone: phone.text.trim(),
        vehicleType: vehicleType.text.trim(),
        plateNumber: plateNumber.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${rider.name} created. They go on duty from the rider app.",
          ),
        ),
      );
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
      appBar: AppBar(title: const Text("Add rider")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Account",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                "The rider signs in with these.",
                style: TextStyle(fontSize: 12, color: kMuted),
              ),

              const SizedBox(height: 14),

              TextFormField(
                controller: username,
                autocorrect: false,
                decoration: _decoration(
                  "Username *",
                  Icons.person_outline,
                  error: _serverErrorFor('username'),
                ),
                validator: (value) {
                  final server = _serverErrorFor('username');
                  if (server != null) return server;
                  return (value == null || value.trim().isEmpty)
                      ? "Enter a username"
                      : null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: password,
                obscureText: _obscure,
                decoration: _decoration(
                  "Password *",
                  Icons.lock_outline,
                  error: _serverErrorFor('password'),
                  helper: "Checked against Django's password validators.",
                  suffix: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (value) {
                  final server = _serverErrorFor('password');
                  if (server != null) return server;
                  return (value == null || value.isEmpty)
                      ? "Enter a password"
                      : null;
                },
              ),

              const SizedBox(height: 26),

              const Text(
                "Rider details",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                "Optional, but the name and phone show on the admin queue and "
                "to the customer during delivery.",
                style: TextStyle(fontSize: 12, color: kMuted),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: firstName,
                      decoration: _decoration("First name", Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: lastName,
                      decoration: _decoration("Last name", Icons.badge_outlined),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: _decoration("Phone", Icons.phone_outlined),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: vehicleType,
                decoration: _decoration(
                  "Vehicle type",
                  Icons.motorcycle,
                  helper: "e.g. Motorcycle",
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: plateNumber,
                textCapitalization: TextCapitalization.characters,
                decoration: _decoration(
                  "Plate number",
                  Icons.confirmation_number_outlined,
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC62828).withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 17,
                        color: Color(0xFFC62828),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFB71C1C),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kInk,
                        ),
                      )
                    : const Icon(Icons.person_add_alt, size: 20),
                label: const Text("Create rider account"),
              ),

              const SizedBox(height: 12),

              const Text(
                "New riders start off duty. They go on duty from their own app.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: kMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(
    String label,
    IconData icon, {
    String? error,
    String? helper,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      errorText: error,
      helperText: helper,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
    );
  }
}
