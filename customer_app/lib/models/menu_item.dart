/// A row from `GET /api/menu/`.
///
/// Django sends money as a decimal string ("250.00") so it never loses
/// precision in transit; it is parsed to a double here for display only.
/// The authoritative price is always the server's.
class MenuItem {
  MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.photo,
    required this.isAvailable,
  });

  final int id;
  final String name;
  final String description;
  final double price;

  /// Absolute URL supplied by the serializer, or null when no photo is set.
  final String? photo;
  final bool isAvailable;

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] as int,
      name: (json['name'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      price: _toDouble(json['price']),
      photo: (json['photo'] as String?)?.isEmpty ?? true
          ? null
          : json['photo'] as String,
      isAvailable: (json['is_available'] ?? true) as bool,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
