class SupplierOrderItem {
  final String itemName;
  final double quantity;
  final String unit;
  final double unitCost;

  SupplierOrderItem({
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.unitCost,
  });

  double get totalPrice => quantity * unitCost;

  factory SupplierOrderItem.fromMap(Map<String, dynamic> map) {
    return SupplierOrderItem(
      itemName: map['item_name'] ?? '',
      quantity: (map['quantity'] ?? 0.0).toDouble(),
      unit: map['unit'] ?? 'lbs',
      unitCost: (map['unit_cost'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'item_name': itemName,
      'quantity': quantity,
      'unit': unit,
      'unit_cost': unitCost,
    };
  }
}

class SupplierOrder {
  final String id;
  final String supplierName;
  final String category;
  final DateTime orderDate;
  final DateTime expectedDeliveryDate;
  final List<SupplierOrderItem> items;
  String status; // 'Pending', 'Delivered', 'Cancelled'
  final String notes;

  SupplierOrder({
    required this.id,
    required this.supplierName,
    required this.category,
    required this.orderDate,
    required this.expectedDeliveryDate,
    required this.items,
    this.status = 'Pending',
    this.notes = '',
  });

  double get totalOrderCost => items.fold(0.0, (sum, i) => sum + i.totalPrice);

  factory SupplierOrder.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? [];
    return SupplierOrder(
      id: map['id'] ?? '',
      supplierName: map['supplier_name'] ?? '',
      category: map['category'] ?? '',
      orderDate: DateTime.tryParse(map['order_date'] ?? '') ?? DateTime.now(),
      expectedDeliveryDate: DateTime.tryParse(map['expected_delivery_date'] ?? '') ?? DateTime.now().add(const Duration(days: 2)),
      status: map['status'] ?? 'Pending',
      notes: map['notes'] ?? '',
      items: rawItems.map((i) => SupplierOrderItem.fromMap(Map<String, dynamic>.from(i))).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier_name': supplierName,
      'category': category,
      'order_date': orderDate.toIso8601String(),
      'expected_delivery_date': expectedDeliveryDate.toIso8601String(),
      'status': status,
      'notes': notes,
      'items': items.map((i) => i.toMap()).toList(),
    };
  }
}
