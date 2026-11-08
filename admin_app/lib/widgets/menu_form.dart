import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/menu_item.dart';
import '../services/api_client.dart';
import '../services/menu_service.dart';
import '../theme.dart';

/// The create/edit form for a menu item.
///
/// One widget for both so the field list, validation and photo handling
/// cannot drift apart. [existing] null means create.
///
/// Pops with `true` when something was saved, so the list knows to refetch.
class MenuForm extends StatefulWidget {
  const MenuForm({super.key, this.existing});

  final MenuItem? existing;

  bool get isEdit => existing != null;

  @override
  State<MenuForm> createState() => _MenuFormState();
}

class _MenuFormState extends State<MenuForm> {
  final _formKey = GlobalKey<FormState>();
  final _menu = MenuService();
  final _picker = ImagePicker();

  late final TextEditingController nameController;
  late final TextEditingController priceController;
  late final TextEditingController descriptionController;

  late bool available;

  /// Newly chosen photo, not yet uploaded. Null means "leave the existing
  /// photo alone" on edit, or "no photo" on create.
  XFile? _photo;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    nameController = TextEditingController(text: existing?.name ?? '');
    priceController = TextEditingController(
      text: existing == null ? '' : existing.price.toStringAsFixed(2),
    );
    descriptionController =
        TextEditingController(text: existing?.description ?? '');
    available = existing?.isAvailable ?? true;
  }

  @override
  void dispose() {
    nameController.dispose();
    priceController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Choose from gallery"),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text("Take a photo"),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text("Cancel"),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final photo = await _picker.pickImage(
        source: source,
        // Menu photos are shown at thumbnail and card size; full-resolution
        // camera output would just be a slow upload.
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (photo == null || !mounted) return;
      setState(() => _photo = photo);
    } on Exception {
      if (!mounted) return;
      setState(() => _error = "Could not open the image picker.");
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    // Django's DecimalField wants a plain decimal string, not a formatted one.
    final price = priceController.text.trim();

    try {
      if (widget.isEdit) {
        await _menu.update(
          widget.existing!.id,
          name: nameController.text.trim(),
          description: descriptionController.text.trim(),
          price: price,
          isAvailable: available,
          photoPath: _photo?.path,
        );
      } else {
        await _menu.create(
          name: nameController.text.trim(),
          description: descriptionController.text.trim(),
          price: price,
          isAvailable: available,
          photoPath: _photo?.path,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? "Edit item" : "Add item"),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _photoPicker()),

              const SizedBox(height: 30),

              TextFormField(
                controller: nameController,
                decoration: _decoration("Item name", Icons.local_pizza),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? "Enter a name"
                        : null,
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration("Price", Icons.attach_money),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return "Enter a price";
                  final parsed = double.tryParse(text);
                  if (parsed == null) return "Enter a number, e.g. 399.00";
                  if (parsed < 0) return "Price cannot be negative";
                  return null;
                },
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: descriptionController,
                maxLines: 4,
                decoration: _decoration(
                  "Description",
                  Icons.description,
                  alignLabelWithHint: true,
                ),
              ),

              const SizedBox(height: 20),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  value: available,
                  activeThumbColor: Colors.white,
                  activeTrackColor: const Color(0xFF2E7D32),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: const Text(
                    "On sale",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                  subtitle: const Text(
                    "Customers can see and order this item",
                    style: TextStyle(fontSize: 12, color: kMuted),
                  ),
                  onChanged: (value) => setState(() => available = value),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
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
                    : const Icon(Icons.save, size: 20),
                label: Text(widget.isEdit ? "Save changes" : "Add to menu"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoPicker() {
    final existingPhoto = widget.existing?.photo;

    Widget preview;
    if (_photo != null) {
      preview = Image.file(File(_photo!.path), fit: BoxFit.cover);
    } else if (existingPhoto != null) {
      preview = Image.network(
        existingPhoto,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(
          Icons.local_pizza,
          size: 54,
          color: Colors.grey,
        ),
      );
    } else {
      preview = const Icon(Icons.local_pizza, size: 54, color: Colors.grey);
    }

    return Stack(
      children: [
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.white,
            // Rounded square, not a circle: the photo is shown as a square
            // thumbnail everywhere else, and a circular preview crops a
            // different part of it than the list will.
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Center(child: preview),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: kAmber,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              onPressed: _saving ? null : _pickPhoto,
              icon: const Icon(Icons.camera_alt, size: 20),
              color: kInk,
              tooltip: "Choose a photo",
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _decoration(
    String label,
    IconData icon, {
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: alignLabelWithHint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
    );
  }
}
