class InventoryItem {
  final String id;
  final String name;
  final String category;
  double quantity;
  final String unit;
  final double reorderLevel;
  final double unitCost;
  DateTime lastUpdated;

  InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.reorderLevel,
    required this.unitCost,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  bool get isLowStock => quantity <= reorderLevel;

  factory InventoryItem.fromMap(Map<String, dynamic> data, String id) {
    return InventoryItem(
      id: id,
      name: data['item_name'] ?? 'Ingredient',
      category: data['category'] ?? 'General',
      quantity: (data['quantity'] ?? 0.0).toDouble(),
      unit: data['unit'] ?? 'units',
      reorderLevel: (data['reorder_level'] ?? 10.0).toDouble(),
      unitCost: (data['unit_cost'] ?? 1.50).toDouble(),
      lastUpdated: data['last_updated'] != null
          ? DateTime.tryParse(data['last_updated'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'item_name': name,
      'category': category,
      'quantity': quantity,
      'unit': unit,
      'reorder_level': reorderLevel,
      'unit_cost': unitCost,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}

class SpoilageRecord {
  final String id;
  final String inventoryId;
  final String itemName;
  final double quantitySpoiled;
  final String unit;
  final String reason;
  final String notes;
  final String recordedByName;
  final DateTime occurredAt;
  final double stockBefore;
  final double stockAfter;
  final String requestId;

  SpoilageRecord({
    required this.id,
    required this.inventoryId,
    required this.itemName,
    required this.quantitySpoiled,
    required this.unit,
    required this.reason,
    required this.notes,
    required this.recordedByName,
    required this.occurredAt,
    required this.stockBefore,
    required this.stockAfter,
    required this.requestId,
  });

  factory SpoilageRecord.fromMap(Map<String, dynamic> data, String id) {
    return SpoilageRecord(
      id: id,
      inventoryId: data['inventory_id'] ?? '',
      itemName: data['item_name'] ?? '',
      quantitySpoiled: (data['quantity_spoiled'] ?? 0.0).toDouble(),
      unit: data['unit'] ?? 'lbs',
      reason: data['reason'] ?? 'Expired',
      notes: data['notes'] ?? '',
      recordedByName: data['recorded_by_name'] ?? 'Staff',
      occurredAt: data['occurred_at'] != null
          ? DateTime.tryParse(data['occurred_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      stockBefore: (data['stock_before'] ?? 0.0).toDouble(),
      stockAfter: (data['stock_after'] ?? 0.0).toDouble(),
      requestId: data['request_id'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'spoilage_id': id,
      'inventory_id': inventoryId,
      'item_name': itemName,
      'quantity_spoiled': quantitySpoiled,
      'unit': unit,
      'reason': reason,
      'notes': notes,
      'recorded_by_name': recordedByName,
      'occurred_at': occurredAt.toIso8601String(),
      'stock_before': stockBefore,
      'stock_after': stockAfter,
      'request_id': requestId,
    };
  }
}
