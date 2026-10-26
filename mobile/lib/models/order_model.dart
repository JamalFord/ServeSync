class OrderItem {
  final String menuItemId;
  final String name;
  final double unitPrice;
  int quantity;
  final String modifications;
  final int seatNumber;

  OrderItem({
    required this.menuItemId,
    required this.name,
    required this.unitPrice,
    this.quantity = 1,
    this.modifications = '',
    this.seatNumber = 1,
  });

  double get totalPrice => unitPrice * quantity;

  factory OrderItem.fromMap(Map<String, dynamic> data) {
    return OrderItem(
      menuItemId: data['menu_item_id'] ?? '',
      name: data['name'] ?? '',
      unitPrice: (data['unit_price'] ?? 0.0).toDouble(),
      quantity: data['quantity'] ?? 1,
      modifications: data['modifications'] ?? '',
      seatNumber: data['seat_number'] ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'menu_item_id': menuItemId,
      'name': name,
      'unit_price': unitPrice,
      'quantity': quantity,
      'modifications': modifications,
      'seat_number': seatNumber,
    };
  }
}

class CustomerOrder {
  final String id;
  final int tableNumber;
  final String serverName;
  final List<OrderItem> items;
  String status; // 'Active', 'Completed', 'Cancelled'
  final DateTime createdAt;
  double get subtotal => items.fold(0.0, (sum, item) => sum + item.totalPrice);
  double get tax => subtotal * 0.0825; // 8.25% sales tax
  double get totalAmount => subtotal + tax;

  CustomerOrder({
    required this.id,
    required this.tableNumber,
    required this.serverName,
    required this.items,
    this.status = 'Active',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory CustomerOrder.fromMap(Map<String, dynamic> data, String id) {
    final rawItems = data['items'] as List<dynamic>? ?? [];
    return CustomerOrder(
      id: id,
      tableNumber: data['table_number'] ?? 1,
      serverName: data['server_name'] ?? 'Server',
      status: data['status'] ?? 'Active',
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      items: rawItems
          .map((i) => OrderItem.fromMap(Map<String, dynamic>.from(i)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'order_id': id,
      'table_number': tableNumber,
      'server_name': serverName,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'total_amount': totalAmount,
      'items': items.map((i) => i.toMap()).toList(),
    };
  }
}
