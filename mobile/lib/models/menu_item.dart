class MenuItem {
  final String id;
  final String name;
  final String category;
  final double price;
  final String description;
  final bool isAvailable;
  final String iconEmoji;
  final Map<String, double> inventoryIngredients; // inventory_id -> qty needed

  MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.description,
    this.isAvailable = true,
    required this.iconEmoji,
    this.inventoryIngredients = const {},
  });

  factory MenuItem.fromMap(Map<String, dynamic> data, String id) {
    return MenuItem(
      id: id,
      name: data['item_name'] ?? 'Item',
      category: data['category'] ?? 'Entrees',
      price: (data['price'] ?? 0.0).toDouble(),
      description: data['description'] ?? '',
      isAvailable: data['available'] ?? true,
      iconEmoji: data['icon_emoji'] ?? '🍽️',
      inventoryIngredients: Map<String, double>.from(data['ingredients'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'item_name': name,
      'category': category,
      'price': price,
      'description': description,
      'available': isAvailable,
      'icon_emoji': iconEmoji,
      'ingredients': inventoryIngredients,
    };
  }
}
