class MenuItem {
  final String id;
  final String name;
  final double price;
  final String image;

  MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.image,
  });

  factory MenuItem.fromMap(String id, Map<String, dynamic> data) {
    return MenuItem(
      id: id,
      name: data['name'],
      price: data['price'].toDouble(),
      image: data['image'],
    );
  }
}