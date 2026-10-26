enum TableStatus {
  available,
  seated,
  ordered,
  checkRequested,
}

class DiningTable {
  final int tableNumber;
  final int capacity;
  TableStatus status;
  int guestCount;
  String? serverName;
  String? activeOrderId;
  double billAmount;
  DateTime? seatedAt;

  DiningTable({
    required this.tableNumber,
    required this.capacity,
    this.status = TableStatus.available,
    this.guestCount = 0,
    this.serverName,
    this.activeOrderId,
    this.billAmount = 0.0,
    this.seatedAt,
  });

  bool get isOccupied => status != TableStatus.available;

  factory DiningTable.fromMap(Map<String, dynamic> data, int tableNumber) {
    TableStatus status = TableStatus.available;
    final statusStr = data['status']?.toString().toLowerCase() ?? 'available';
    if (statusStr.contains('seat')) {
      status = TableStatus.seated;
    } else if (statusStr.contains('order')) {
      status = TableStatus.ordered;
    } else if (statusStr.contains('check')) {
      status = TableStatus.checkRequested;
    }

    return DiningTable(
      tableNumber: tableNumber,
      capacity: data['capacity'] ?? 4,
      status: status,
      guestCount: data['guest_count'] ?? 0,
      serverName: data['server_name'],
      activeOrderId: data['active_order_id'],
      billAmount: (data['bill_amount'] ?? 0.0).toDouble(),
      seatedAt: data['seated_at'] != null
          ? DateTime.tryParse(data['seated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'table_number': tableNumber,
      'capacity': capacity,
      'status': status.name,
      'guest_count': guestCount,
      'server_name': serverName,
      'active_order_id': activeOrderId,
      'bill_amount': billAmount,
      'seated_at': seatedAt?.toIso8601String(),
    };
  }
}
