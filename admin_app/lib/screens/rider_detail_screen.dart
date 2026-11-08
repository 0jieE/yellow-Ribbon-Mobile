import 'package:flutter/material.dart';

import '../models/rider_model.dart';
import '../services/api_client.dart';
import '../services/rider_admin_service.dart';
import '../theme.dart';
import '../widgets/section_card.dart';

/// One rider's account: edit their details, reset their password, switch the
/// account off.
///
/// Pops with `true` when anything changed, so the roster refetches.
class RiderDetailScreen extends StatefulWidget {
  const RiderDetailScreen({super.key, required this.rider});

  final Rider rider;

  @override
  State<RiderDetailScreen> createState() => _RiderDetailScreenState();
}

class _RiderDetailScreenState extends State<RiderDetailScreen> {
  final _riders = RiderAdminService();
  final _formKey = GlobalKey<FormState>();

  late Rider _rider;

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _vehicleType;
  late final TextEditingController _plateNumber;

  bool _saving = false;
  bool _switching = false;
  bool _dirty = false;

  /// Field errors from the last save, so a rejected value lands under its
  /// box instead of in a snackbar.
  Map<String, dynamic> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    _rider = widget.rider;
    _firstName = TextEditingController(text: _rider.firstName);
    _lastName = TextEditingController(text: _rider.lastName);
    _phone = TextEditingController(text: _rider.phone);
    _vehicleType = TextEditingController(text: _rider.vehicleType);
    _plateNumber = TextEditingController(text: _rider.plateNumber);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _vehicleType.dispose();
    _plateNumber.dispose();
    super.dispose();
  }

  String? _serverErrorFor(String field) {
    final detail = _fieldErrors[field];
    if (detail is List && detail.isNotEmpty) return '${detail.first}';
    if (detail is String && detail.isNotEmpty) return detail;
    return null;
  }

  // -- actions -----------------------------------------------------------

  Future<void> _save() async {
    setState(() {
      _fieldErrors = const {};
      _saving = true;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() => _saving = false);
      return;
    }

    try {
      final updated = await _riders.update(
        _rider.id,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim(),
        vehicleType: _vehicleType.text.trim(),
        plateNumber: _plateNumber.text.trim(),
      );
      if (!mounted) return;

      setState(() {
        _rider = updated;
        _saving = false;
        _dirty = true;
      });
      _snack("Saved.");
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _fieldErrors = e.fields ?? const {};
      });
      // Re-run validation so a server field error renders under its input.
      _formKey.currentState!.validate();
      if (_fieldErrors.isEmpty) _snack(e.message);
    }
  }

  Future<void> _setPassword() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _SetPasswordDialog(
        riderId: _rider.id,
        username: _rider.username,
        riders: _riders,
      ),
    );

    if (password == null || !mounted) return;
    _dirty = true;
    _snack("Password updated for ${_rider.username}.");
  }

  Future<void> _toggleActive() async {
    final turningOff = _rider.isActive;

    if (turningOff) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text("Deactivate ${_rider.name}?"),
          content: const Text(
            "They will not be able to sign in, and they will drop out of the "
            "assignment list. Nothing is deleted — their delivery history "
            "stays intact, and you can switch the account back on.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
                foregroundColor: Colors.white,
                minimumSize: const Size(110, 44),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Deactivate"),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _switching = true);

    try {
      final updated = await _riders.setActive(_rider.id, !turningOff);
      if (!mounted) return;
      setState(() {
        _rider = updated;
        _switching = false;
        _dirty = true;
      });
      _snack(turningOff ? "Account deactivated." : "Account restored.");
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _switching = false);
      // The server refuses while the rider is still carrying orders, and its
      // message names them. That is worth a dialog, not a snackbar.
      await _showRefusal(e.message);
    }
  }

  Future<void> _showRefusal(String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.block, color: Color(0xFFC62828), size: 30),
        title: const Text("Cannot deactivate yet"),
        content: Text(message),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(88, 42)),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Got it"),
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

  // -- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _dirty);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Rider account"),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _dirty),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _Header(rider: _rider),

              const SizedBox(height: 14),

              SectionCard(
                title: "Details",
                icon: Icons.badge_outlined,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            _firstName,
                            "First name",
                            Icons.person_outline,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(
                            _lastName,
                            "Last name",
                            Icons.person_outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _phone,
                      "Phone",
                      Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: (_) => _serverErrorFor('phone'),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _vehicleType,
                      "Vehicle type",
                      Icons.motorcycle,
                      validator: (_) => _serverErrorFor('vehicle_type'),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _plateNumber,
                      "Plate number",
                      Icons.confirmation_number_outlined,
                      capitalise: true,
                      validator: (_) => _serverErrorFor('plate_number'),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "The username cannot be changed — it is what the rider "
                      "signs in with and what their history is read against.",
                      style: TextStyle(fontSize: 11.5, color: kMuted),
                    ),

                    const SizedBox(height: 14),

                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kInk,
                              ),
                            )
                          : const Icon(Icons.save, size: 19),
                      label: const Text("Save changes"),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              SectionCard(
                title: "Password",
                icon: Icons.key_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "Riders have no self-service reset, so this is the only "
                      "way back in for a locked-out account.",
                      style: TextStyle(fontSize: 12.5, color: kMuted),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _setPassword,
                      icon: const Icon(Icons.lock_reset, size: 19),
                      label: const Text("Set a new password"),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              SectionCard(
                title: _rider.isActive ? "Deactivate" : "Reactivate",
                icon: _rider.isActive
                    ? Icons.person_off_outlined
                    : Icons.person_add_alt,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _rider.isActive
                          ? "Blocks sign-in and removes them from the "
                              "assignment list. Their delivery history is kept "
                              "— accounts are never deleted."
                          : "This account is switched off. Restoring it lets "
                              "them sign in again; they still have to go on "
                              "duty from their own app.",
                      style: const TextStyle(fontSize: 12.5, color: kMuted),
                    ),

                    // Warn before the server has to. Deactivation is refused
                    // while a rider still holds orders, and saying so here
                    // beats a dialog after the tap.
                    if (_rider.isActive && _rider.isHolding) ...[
                      const SizedBox(height: 11),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB26A00).withValues(alpha: .11),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Color(0xFFB26A00),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                "Still carrying ${_rider.workloadLabel}. "
                                "Reassign or finish those first.",
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    OutlinedButton.icon(
                      onPressed: _switching ? null : _toggleActive,
                      icon: _switching
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _rider.isActive
                                  ? Icons.person_off_outlined
                                  : Icons.check_circle_outline,
                              size: 19,
                            ),
                      label: Text(
                        _rider.isActive
                            ? "Deactivate account"
                            : "Restore account",
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _rider.isActive
                            ? const Color(0xFFC62828)
                            : const Color(0xFF2E7D32),
                        side: BorderSide(
                          color: _rider.isActive
                              ? const Color(0xFFC62828)
                              : const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    bool capitalise = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization:
          capitalise ? TextCapitalization.characters : TextCapitalization.words,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 19, color: kMuted),
        fillColor: kCanvas,
        labelStyle: const TextStyle(fontSize: 13.5, color: kMuted),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.rider});

  final Rider rider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kInk,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rider.isActive ? kAmber : Colors.white24,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.delivery_dining,
              color: rider.isActive ? kInk : Colors.white70,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rider.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "@${rider.username}",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
                if (rider.isHolding) ...[
                  const SizedBox(height: 7),
                  Text(
                    rider.workloadLabel,
                    style: const TextStyle(
                      color: kAmber,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!rider.isActive)
            const TagPill(
              label: "Deactivated",
              colour: Color(0xFFEF9A9A),
              icon: Icons.person_off_outlined,
            ),
        ],
      ),
    );
  }
}

/// Sets a rider's password, keeping Django's validator message under the box.
class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog({
    required this.riderId,
    required this.username,
    required this.riders,
  });

  final int riderId;
  final String username;
  final RiderAdminService riders;

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _controller = TextEditingController();

  bool _obscured = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = "Enter a password.");
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.riders.setPassword(widget.riderId, password);
      if (!mounted) return;
      Navigator.pop(context, password);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Django's validators come back under `fields.password`, one string
        // per rule broken. All of them are worth reading.
        _error = _passwordError(e) ?? e.message;
      });
    }
  }

  String? _passwordError(ApiException e) {
    final detail = e.fields?['password'];
    if (detail is List && detail.isNotEmpty) {
      return detail.map((line) => '$line').join('\n');
    }
    if (detail is String && detail.isNotEmpty) return detail;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("New password for ${widget.username}"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Tell the rider yourself — they are not notified.",
            style: TextStyle(fontSize: 12.5, color: kMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            obscureText: _obscured,
            autofocus: true,
            onSubmitted: (_) => _saving ? null : _submit(),
            decoration: InputDecoration(
              hintText: "New password",
              fillColor: kCanvas,
              errorText: _error,
              errorMaxLines: 4,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscured ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: kMuted,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(110, 44)),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kInk,
                  ),
                )
              : const Text("Set password"),
        ),
      ],
    );
  }
}
