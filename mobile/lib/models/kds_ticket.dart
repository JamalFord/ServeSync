enum TicketStatus {
  newOrder,
  inPrep,
  ready,
  served,
}

class KDSTicketItem {
  final String name;
  final int quantity;
  final String modifications;

  KDSTicketItem({
    required this.name,
    required this.quantity,
    this.modifications = '',
  });

  factory KDSTicketItem.fromMap(Map<String, dynamic> data) {
    return KDSTicketItem(
      name: data['name'] ?? '',
      quantity: data['quantity'] ?? 1,
      modifications: data['modifications'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'modifications': modifications,
    };
  }
}

class KDSTicket {
  final String id;
  final String orderId;
  final int tableNumber;
  final String serverName;
  TicketStatus status;
  final DateTime orderTime;
  final List<KDSTicketItem> items;

  KDSTicket({
    required this.id,
    required this.orderId,
    required this.tableNumber,
    required this.serverName,
    this.status = TicketStatus.newOrder,
    DateTime? orderTime,
    required this.items,
  }) : orderTime = orderTime ?? DateTime.now();

  int get elapsedMinutes => DateTime.now().difference(orderTime).inMinutes;

  factory KDSTicket.fromMap(Map<String, dynamic> data, String id) {
    TicketStatus status = TicketStatus.newOrder;
    final statusStr = data['status']?.toString().toLowerCase() ?? 'new';
    if (statusStr.contains('prep')) {
      status = TicketStatus.inPrep;
    } else if (statusStr.contains('ready')) {
      status = TicketStatus.ready;
    } else if (statusStr.contains('served')) {
      status = TicketStatus.served;
    }

    final rawItems = data['items'] as List<dynamic>? ?? [];
    return KDSTicket(
      id: id,
      orderId: data['order_id'] ?? '',
      tableNumber: data['table_number'] ?? 1,
      serverName: data['server_name'] ?? 'Server',
      status: status,
      orderTime: data['order_time'] != null
          ? DateTime.tryParse(data['order_time'].toString()) ?? DateTime.now()
          : DateTime.now(),
      items: rawItems
          .map((i) => KDSTicketItem.fromMap(Map<String, dynamic>.from(i)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ticket_id': id,
      'order_id': orderId,
      'table_number': tableNumber,
      'server_name': serverName,
      'status': status.name,
      'order_time': orderTime.toIso8601String(),
      'items': items.map((i) => i.toMap()).toList(),
    };
  }
}
