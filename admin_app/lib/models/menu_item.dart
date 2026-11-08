/// A row from `GET /api/menu/`.
///
/// Django sends money as a decimal string ("399.00") so it never loses
/// precision in transit; it is parsed to a double for display and sent back
/// as a string on write.
class MenuItem {
  MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.isAvailable,
    this.photo,
  });

  final int id;
  final String name;
  final String description;
  final double price;
  final bool isAvailable;

  /// Absolute URL supplied by the serializer, or null when no photo is set.
  final String? photo;

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    final photo = json['photo'] as String?;
    return MenuItem(
      id: (json['id'] ?? 0) as int,
      name: (json['name'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      price: _toDouble(json['price']),
      isAvailable: (json['is_available'] ?? true) as bool,
      photo: (photo == null || photo.isEmpty) ? null : photo,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
