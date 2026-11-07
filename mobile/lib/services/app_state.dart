import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/employee.dart';
import '../models/table_model.dart';
import '../models/menu_item.dart';
import '../models/order_model.dart';
import '../models/kds_ticket.dart';
import '../models/inventory_item.dart';
import '../models/supplier_order.dart';
import '../theme/app_theme.dart';

class AppState extends ChangeNotifier {
  static final AppState instance = AppState._internal();
  AppState._internal() {
    _initSeedData();
    _tryInitFirestore();
  }

  final _uuid = const Uuid();
  FirebaseFirestore? _firestore;

  // Active Theme Preset
  ThemePreset currentTheme = ThemePreset.midnightEmber;

  void setTheme(ThemePreset preset) {
    currentTheme = preset;
    AppTheme.setPreset(preset);
    notifyListeners();
  }

  // Active Session
  Employee? currentEmployee;
  final List<Employee> employees = [];

  // Floor Plan
  final List<DiningTable> tables = [];

  // Menu Catalog
  final List<MenuItem> menuCatalog = [];

  // Current Cart for POS
  int? selectedTableForOrder;
  final List<OrderItem> currentCart = [];

  // Active Orders
  final List<CustomerOrder> orders = [];

  // KDS Tickets
  final List<KDSTicket> kdsTickets = [];

  // Inventory & Spoilage
  final List<InventoryItem> inventory = [];
  final List<SpoilageRecord> spoilageHistory = [];
  final List<SupplierOrder> supplierOrders = [];

  // Connection indicator
  bool isFirestoreConnected = false;

  void _tryInitFirestore() {
    try {
      _firestore = FirebaseFirestore.instance;
      isFirestoreConnected = true;
      _listenToFirestore();
    } catch (e) {
      debugPrint('Firestore not available or running offline: $e');
      isFirestoreConnected = false;
    }
  }

  void _listenToFirestore() {
    if (_firestore == null) return;
    try {
      _firestore!.collection('kds_tickets').snapshots().listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          kdsTickets.clear();
          for (var doc in snapshot.docs) {
            kdsTickets.add(KDSTicket.fromMap(doc.data(), doc.id));
          }
          notifyListeners();
        }
      }, onError: (e) {
        debugPrint('Firestore kds stream error: $e');
      });
    } catch (e) {
      debugPrint('Error attaching firestore stream: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Seed Data Initializer
  // --------------------------------------------------------------------------
  void _initSeedData() {
    // 1. Employees
    employees.addAll([
      Employee(
        id: 'emp_01',
        name: 'Salem Marye',
        role: 'Administrator',
        pin: '1234',
        hourlyRate: 28.00,
        isClockedIn: true,
        clockInTime: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      Employee(
        id: 'emp_02',
        name: 'Jamal Ford',
        role: 'Manager',
        pin: '2345',
        hourlyRate: 22.50,
        isClockedIn: true,
        clockInTime: DateTime.now().subtract(const Duration(hours: 4, minutes: 15)),
      ),
      Employee(
        id: 'emp_03',
        name: 'Alex Rivera',
        role: 'FOH Staff',
        pin: '3456',
        hourlyRate: 16.50,
        isClockedIn: false,
      ),
    ]);

    // Default active user is Manager Jamal
    currentEmployee = employees[1];

    // 2. Dining Tables
    tables.addAll([
      DiningTable(tableNumber: 1, capacity: 2, status: TableStatus.available),
      DiningTable(
        tableNumber: 2,
        capacity: 4,
        status: TableStatus.ordered,
        guestCount: 3,
        serverName: 'Jamal Ford',
        billAmount: 68.50,
        seatedAt: DateTime.now().subtract(const Duration(minutes: 25)),
      ),
      DiningTable(
        tableNumber: 3,
        capacity: 4,
        status: TableStatus.seated,
        guestCount: 4,
        serverName: 'Salem Marye',
        seatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
      DiningTable(tableNumber: 4, capacity: 6, status: TableStatus.available),
      DiningTable(
        tableNumber: 5,
        capacity: 4,
        status: TableStatus.checkRequested,
        guestCount: 2,
        serverName: 'Alex Rivera',
        billAmount: 94.20,
        seatedAt: DateTime.now().subtract(const Duration(minutes: 55)),
      ),
      DiningTable(tableNumber: 6, capacity: 2, status: TableStatus.available),
      DiningTable(tableNumber: 7, capacity: 8, status: TableStatus.available),
      DiningTable(
        tableNumber: 8,
        capacity: 4,
        status: TableStatus.ordered,
        guestCount: 4,
        serverName: 'Jamal Ford',
        billAmount: 112.00,
        seatedAt: DateTime.now().subtract(const Duration(minutes: 18)),
      ),
    ]);

    // 3. Menu Items
    menuCatalog.addAll([
      MenuItem(
        id: 'm_01',
        name: 'Truffle Parmesan Fries',
        category: 'Appetizers',
        price: 12.00,
        description: 'Hand-cut russet potatoes, white truffle oil, shaved parmesan, garlic aioli',
        iconEmoji: '🍟',
        inventoryIngredients: {'inv_potatoes': 0.75, 'inv_truffle': 0.05},
      ),
      MenuItem(
        id: 'm_02',
        name: 'Crispy Calamari',
        category: 'Appetizers',
        price: 15.50,
        description: 'Point Judith squid, pickled cherry peppers, citrus remoulade',
        iconEmoji: '🦑',
        inventoryIngredients: {'inv_calamari': 0.50},
      ),
      MenuItem(
        id: 'm_03',
        name: 'ServeSync Smash Burger',
        category: 'Entrees',
        price: 18.00,
        description: 'Double Angus beef patties, aged cheddar, caramelized shallots, brioche bun',
        iconEmoji: '🍔',
        inventoryIngredients: {'inv_beef': 0.50, 'inv_buns': 1.0, 'inv_cheese': 0.15},
      ),
      MenuItem(
        id: 'm_04',
        name: 'Pan-Roasted Atlantic Salmon',
        category: 'Entrees',
        price: 26.50,
        description: 'Crispy skin salmon, sweet corn succotash, charred tomato beurre blanc',
        iconEmoji: '🐟',
        inventoryIngredients: {'inv_salmon': 0.60, 'inv_tomatoes': 0.30},
      ),
      MenuItem(
        id: 'm_05',
        name: 'Wild Mushroom Risotto',
        category: 'Entrees',
        price: 22.00,
        description: 'Arborio rice, cremini & shiitake mushrooms, mascarpone, thyme',
        iconEmoji: '🍄',
        inventoryIngredients: {'inv_mushrooms': 0.40},
      ),
      MenuItem(
        id: 'm_06',
        name: 'Smoked Hibiscus Spritz',
        category: 'Beverages',
        price: 9.50,
        description: 'Brewed hibiscus petals, fresh lime, agave, sparkling water, mint sprig',
        iconEmoji: '🍹',
        inventoryIngredients: {'inv_mint': 0.05},
      ),
      MenuItem(
        id: 'm_07',
        name: 'Craft Cold Brew & Tonic',
        category: 'Beverages',
        price: 6.00,
        description: 'Single-origin Ethiopian cold brew, fever-tree tonic, orange twist',
        iconEmoji: '☕',
        inventoryIngredients: {},
      ),
      MenuItem(
        id: 'm_08',
        name: 'Warm Molten Lava Cake',
        category: 'Desserts',
        price: 11.00,
        description: 'Valrhona dark chocolate cake, vanilla bean gelato, raspberry coulis',
        iconEmoji: '🍫',
        inventoryIngredients: {},
      ),
    ]);

    // 4. Inventory Items
    inventory.addAll([
      InventoryItem(
        id: 'inv_beef',
        name: 'Ground Angus Beef',
        category: 'Meat',
        quantity: 38.5,
        unit: 'lbs',
        reorderLevel: 15.0,
        unitCost: 5.20,
      ),
      InventoryItem(
        id: 'inv_salmon',
        name: 'Fresh Atlantic Salmon Fillets',
        category: 'Seafood',
        quantity: 18.0,
        unit: 'lbs',
        reorderLevel: 10.0,
        unitCost: 11.50,
      ),
      InventoryItem(
        id: 'inv_tomatoes',
        name: 'Vine-Ripened Tomatoes',
        category: 'Produce',
        quantity: 8.5, // Intentionally low for visual warning demo!
        unit: 'lbs',
        reorderLevel: 12.0,
        unitCost: 1.80,
      ),
      InventoryItem(
        id: 'inv_buns',
        name: 'Artisan Brioche Buns',
        category: 'Bakery',
        quantity: 56.0,
        unit: 'units',
        reorderLevel: 24.0,
        unitCost: 0.85,
      ),
      InventoryItem(
        id: 'inv_cheese',
        name: 'Aged White Cheddar Slices',
        category: 'Dairy',
        quantity: 14.0,
        unit: 'lbs',
        reorderLevel: 5.0,
        unitCost: 4.25,
      ),
      InventoryItem(
        id: 'inv_potatoes',
        name: 'Russet Potatoes',
        category: 'Produce',
        quantity: 65.0,
        unit: 'lbs',
        reorderLevel: 25.0,
        unitCost: 0.65,
      ),
      InventoryItem(
        id: 'inv_calamari',
        name: 'Cleaned Calamari Tubes & Tentacles',
        category: 'Seafood',
        quantity: 12.0,
        unit: 'lbs',
        reorderLevel: 8.0,
        unitCost: 7.40,
      ),
    ]);

    // 5. Initial Seed KDS Tickets
    kdsTickets.addAll([
      KDSTicket(
        id: 'kds_101',
        orderId: 'ord_101',
        tableNumber: 2,
        serverName: 'Jamal Ford',
        status: TicketStatus.inPrep,
        orderTime: DateTime.now().subtract(const Duration(minutes: 12)),
        items: [
          KDSTicketItem(name: 'ServeSync Smash Burger', quantity: 2, modifications: 'Medium, No Onions on 1'),
          KDSTicketItem(name: 'Truffle Parmesan Fries', quantity: 1, modifications: 'Extra Aioli'),
        ],
      ),
      KDSTicket(
        id: 'kds_102',
        orderId: 'ord_102',
        tableNumber: 8,
        serverName: 'Jamal Ford',
        status: TicketStatus.newOrder,
        orderTime: DateTime.now().subtract(const Duration(minutes: 3)),
        items: [
          KDSTicketItem(name: 'Pan-Roasted Atlantic Salmon', quantity: 2, modifications: 'Gluten-Free'),
          KDSTicketItem(name: 'Crispy Calamari', quantity: 1),
          KDSTicketItem(name: 'Wild Mushroom Risotto', quantity: 1),
        ],
      ),
    ]);

    // 6. Recent Spoilage Seed Record
    spoilageHistory.add(
      SpoilageRecord(
        id: 'spoil_01',
        inventoryId: 'inv_tomatoes',
        itemName: 'Vine-Ripened Tomatoes',
        quantitySpoiled: 4.0,
        unit: 'lbs',
        reason: 'Expired / Overripe',
        notes: 'Excess soft spots found during morning line prep',
        recordedByName: 'Jamal Ford',
        occurredAt: DateTime.now().subtract(const Duration(hours: 5)),
        stockBefore: 12.5,
        stockAfter: 8.5,
        requestId: 'REQ-SEED-SPOIL-1',
      ),
    );

    // 7. Seed Supplier Purchase Orders (UC-05)
    supplierOrders.addAll([
      SupplierOrder(
        id: 'PO-2026-081',
        supplierName: 'Metro Farm Produce Co.',
        category: 'Produce',
        orderDate: DateTime.now().subtract(const Duration(days: 1)),
        expectedDeliveryDate: DateTime.now().add(const Duration(hours: 4)),
        status: 'Pending',
        notes: 'Restock vine-ripened tomatoes & russet potatoes for weekend rush',
        items: [
          SupplierOrderItem(itemName: 'Vine-Ripened Tomatoes', quantity: 25.0, unit: 'lbs', unitCost: 1.80),
          SupplierOrderItem(itemName: 'Russet Potatoes', quantity: 50.0, unit: 'lbs', unitCost: 0.65),
        ],
      ),
      SupplierOrder(
        id: 'PO-2026-079',
        supplierName: 'Buckhead Prime Meats',
        category: 'Meat',
        orderDate: DateTime.now().subtract(const Duration(days: 3)),
        expectedDeliveryDate: DateTime.now().subtract(const Duration(days: 1)),
        status: 'Delivered',
        notes: 'Weekly fresh chuck beef delivery',
        items: [
          SupplierOrderItem(itemName: 'Ground Angus Beef', quantity: 40.0, unit: 'lbs', unitCost: 5.20),
        ],
      ),
      SupplierOrder(
        id: 'PO-2026-078',
        supplierName: 'Atlantic Seafood Wholesalers',
        category: 'Seafood',
        orderDate: DateTime.now().subtract(const Duration(days: 4)),
        expectedDeliveryDate: DateTime.now().subtract(const Duration(days: 2)),
        status: 'Delivered',
        notes: 'Fresh salmon & calamari delivery',
        items: [
          SupplierOrderItem(itemName: 'Fresh Atlantic Salmon Fillets', quantity: 20.0, unit: 'lbs', unitCost: 11.50),
          SupplierOrderItem(itemName: 'Cleaned Calamari Tubes', quantity: 15.0, unit: 'lbs', unitCost: 7.40),
        ],
      ),
    ]);
  }

  // --------------------------------------------------------------------------
  // Authentication & Clock In / Out (UC-01, UC-08)
  // --------------------------------------------------------------------------
  bool authenticateWithPin(String pin) {
    final matched = employees.firstWhere(
      (e) => e.pin == pin,
      orElse: () => Employee(id: '', name: '', role: '', pin: '', hourlyRate: 0),
    );

    if (matched.id.isNotEmpty) {
      currentEmployee = matched;
      notifyListeners();
      return true;
    }
    return false;
  }

  void switchEmployee(Employee employee) {
    currentEmployee = employee;
    notifyListeners();
  }

  void updateEmployeeHourlyRate(String empId, double newRate) {
    final idx = employees.indexWhere((e) => e.id == empId);
    if (idx >= 0) {
      final old = employees[idx];
      employees[idx] = Employee(
        id: old.id,
        name: old.name,
        role: old.role,
        pin: old.pin,
        hourlyRate: newRate,
        isClockedIn: old.isClockedIn,
        clockInTime: old.clockInTime,
      );
      if (currentEmployee?.id == empId) {
        currentEmployee = employees[idx];
      }
      notifyListeners();
    }
  }

  void toggleShift() {
    if (currentEmployee == null) return;
    if (currentEmployee!.isClockedIn) {
      currentEmployee!.isClockedIn = false;
      currentEmployee!.clockInTime = null;
    } else {
      currentEmployee!.isClockedIn = true;
      currentEmployee!.clockInTime = DateTime.now();
    }
    notifyListeners();
    _pushEmployeeUpdate(currentEmployee!);
  }

  void _pushEmployeeUpdate(Employee emp) {
    if (_firestore == null) return;
    try {
      _firestore!.collection('users').doc(emp.id).set(emp.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore employee update failed: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Table Floor Plan Management
  // --------------------------------------------------------------------------
  void selectFloorPlanTable(int tableNumber) {
    selectedTableForOrder = tableNumber;
    notifyListeners();
  }

  void seatGuests(int tableNumber, int guestCount) {
    final table = tables.firstWhere((t) => t.tableNumber == tableNumber);
    table.status = TableStatus.seated;
    table.guestCount = guestCount;
    table.serverName = currentEmployee?.name ?? 'Server';
    table.seatedAt = DateTime.now();
    notifyListeners();
    _pushTableUpdate(table);
  }

  void clearTable(int tableNumber) {
    final table = tables.firstWhere((t) => t.tableNumber == tableNumber);
    table.status = TableStatus.available;
    table.guestCount = 0;
    table.billAmount = 0.0;
    table.activeOrderId = null;
    table.seatedAt = null;
    notifyListeners();
    _pushTableUpdate(table);
  }

  void _pushTableUpdate(DiningTable table) {
    if (_firestore == null) return;
    try {
      _firestore!.collection('tables').doc('table_${table.tableNumber}').set(table.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore table update failed: $e');
    }
  }

  // --------------------------------------------------------------------------
  // POS Cart & Order Dispatch (UC-02)
  // --------------------------------------------------------------------------
  void addToCart(MenuItem item, {String modifications = '', int seatNumber = 1}) {
    final existingIndex = currentCart.indexWhere(
      (c) => c.menuItemId == item.id && c.modifications == modifications && c.seatNumber == seatNumber,
    );

    if (existingIndex >= 0) {
      currentCart[existingIndex].quantity += 1;
    } else {
      currentCart.add(OrderItem(
        menuItemId: item.id,
        name: item.name,
        unitPrice: item.price,
        quantity: 1,
        modifications: modifications,
        seatNumber: seatNumber,
      ));
    }
    notifyListeners();
  }

  void decrementCartItem(int index) {
    if (index >= 0 && index < currentCart.length) {
      if (currentCart[index].quantity > 1) {
        currentCart[index].quantity -= 1;
      } else {
        currentCart.removeAt(index);
      }
      notifyListeners();
    }
  }

  void updateCartItemSeat(int index, int newSeat) {
    if (index >= 0 && index < currentCart.length) {
      final old = currentCart[index];
      currentCart[index] = OrderItem(
        menuItemId: old.menuItemId,
        name: old.name,
        unitPrice: old.unitPrice,
        quantity: old.quantity,
        modifications: old.modifications,
        seatNumber: newSeat,
      );
      notifyListeners();
    }
  }

  void removeCartItem(int index) {
    if (index >= 0 && index < currentCart.length) {
      currentCart.removeAt(index);
      notifyListeners();
    }
  }

  void clearCart() {
    currentCart.clear();
    notifyListeners();
  }

  double get cartSubtotal => currentCart.fold(0.0, (sub, i) => sub + i.totalPrice);
  double get cartTax => cartSubtotal * 0.0825;
  double get cartTotal => cartSubtotal + cartTax;

  /// Submits the current active cart to the Kitchen and updates table state & inventory
  bool submitOrderToKitchen(int tableNumber) {
    if (currentCart.isEmpty) return false;

    final orderId = 'ORD-${_uuid.v4().substring(0, 8).toUpperCase()}';
    final ticketId = 'KDS-${_uuid.v4().substring(0, 6).toUpperCase()}';
    final serverName = currentEmployee?.name ?? 'Server';

    // 1. Create Customer Order
    final newOrder = CustomerOrder(
      id: orderId,
      tableNumber: tableNumber,
      serverName: serverName,
      items: List.from(currentCart),
      createdAt: DateTime.now(),
    );
    orders.insert(0, newOrder);

    // 2. Create Kitchen Display System (KDS) Ticket
    final ticket = KDSTicket(
      id: ticketId,
      orderId: orderId,
      tableNumber: tableNumber,
      serverName: serverName,
      status: TicketStatus.newOrder,
      orderTime: DateTime.now(),
      items: currentCart.map((item) => KDSTicketItem(
        name: item.name,
        quantity: item.quantity,
        modifications: item.modifications,
        seatNumber: item.seatNumber,
      )).toList(),
    );
    kdsTickets.insert(0, ticket);

    // 3. Update Table Status & Bill
    final table = tables.firstWhere((t) => t.tableNumber == tableNumber);
    table.status = TableStatus.ordered;
    table.activeOrderId = orderId;
    table.billAmount += newOrder.totalAmount;
    table.serverName = serverName;

    // 4. Smart Inventory Auto-Deduction (Live Feature)
    for (final item in currentCart) {
      final menuItem = menuCatalog.firstWhere(
        (m) => m.id == item.menuItemId,
        orElse: () => MenuItem(id: '', name: '', category: '', price: 0, description: '', iconEmoji: ''),
      );
      if (menuItem.id.isNotEmpty) {
        menuItem.inventoryIngredients.forEach((invId, qtyPerServing) {
          final invItemIndex = inventory.indexWhere((inv) => inv.id == invId);
          if (invItemIndex >= 0) {
            final deductTotal = qtyPerServing * item.quantity;
            inventory[invItemIndex].quantity = (inventory[invItemIndex].quantity - deductTotal).clamp(0.0, 9999.0);
            inventory[invItemIndex].lastUpdated = DateTime.now();
          }
        });
      }
    }

    // 5. Clear Cart
    currentCart.clear();
    notifyListeners();

    // 6. Push to Firestore if connected
    _pushOrderToFirestore(newOrder, ticket, table);

    return true;
  }

  void _pushOrderToFirestore(CustomerOrder order, KDSTicket ticket, DiningTable table) {
    if (_firestore == null) return;
    try {
      _firestore!.collection('customerOrders').doc(order.id).set(order.toMap());
      _firestore!.collection('kds_tickets').doc(ticket.id).set(ticket.toMap());
      _pushTableUpdate(table);
    } catch (e) {
      debugPrint('Firestore order push failed: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Kitchen Display System (KDS) State Transitions
  // --------------------------------------------------------------------------
  void advanceKDSTicket(String ticketId) {
    final index = kdsTickets.indexWhere((t) => t.id == ticketId);
    if (index >= 0) {
      final ticket = kdsTickets[index];
      switch (ticket.status) {
        case TicketStatus.newOrder:
          ticket.status = TicketStatus.inPrep;
          break;
        case TicketStatus.inPrep:
          ticket.status = TicketStatus.ready;
          break;
        case TicketStatus.ready:
          ticket.status = TicketStatus.served;
          break;
        case TicketStatus.served:
          // Already served, remove or archive
          kdsTickets.removeAt(index);
          break;
      }
      notifyListeners();
      _pushKDSTicketUpdate(ticket);
    }
  }

  void _pushKDSTicketUpdate(KDSTicket ticket) {
    if (_firestore == null) return;
    try {
      _firestore!.collection('kds_tickets').doc(ticket.id).set(ticket.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore KDS update failed: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Inventory Spoilage Logging (UC-11)
  // --------------------------------------------------------------------------
  bool logInventorySpoilage({
    required String inventoryId,
    required double quantitySpoiled,
    required String reason,
    required String notes,
  }) {
    final invIndex = inventory.indexWhere((i) => i.id == inventoryId);
    if (invIndex < 0) return false;

    final item = inventory[invIndex];
    if (quantitySpoiled > item.quantity) {
      return false; // Cannot spoil more than available stock
    }

    final stockBefore = item.quantity;
    final stockAfter = stockBefore - quantitySpoiled;
    item.quantity = stockAfter;
    item.lastUpdated = DateTime.now();

    final spoilageId = 'SPL-${_uuid.v4().substring(0, 8).toUpperCase()}';
    final requestId = 'REQ-${_uuid.v4().substring(0, 10).toUpperCase()}';

    final record = SpoilageRecord(
      id: spoilageId,
      inventoryId: item.id,
      itemName: item.name,
      quantitySpoiled: quantitySpoiled,
      unit: item.unit,
      reason: reason,
      notes: notes,
      recordedByName: currentEmployee?.name ?? 'Manager',
      occurredAt: DateTime.now(),
      stockBefore: stockBefore,
      stockAfter: stockAfter,
      requestId: requestId,
    );

    spoilageHistory.insert(0, record);
    notifyListeners();

    _pushSpoilageToFirestore(record, item);
    return true;
  }

  void _pushSpoilageToFirestore(SpoilageRecord record, InventoryItem item) {
    if (_firestore == null) return;
    try {
      _firestore!.collection('spoilageRecords').doc(record.id).set(record.toMap());
      _firestore!.collection('inventory').doc(item.id).set(item.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore spoilage push failed: $e');
    }
  }

  void createSupplierOrder({
    required String supplierName,
    required String category,
    required String notes,
    required List<SupplierOrderItem> items,
  }) {
    final orderId = 'PO-2026-${_uuid.v4().substring(0, 4).toUpperCase()}';
    supplierOrders.insert(
      0,
      SupplierOrder(
        id: orderId,
        supplierName: supplierName,
        category: category,
        orderDate: DateTime.now(),
        expectedDeliveryDate: DateTime.now().add(const Duration(days: 2)),
        status: 'Pending',
        notes: notes,
        items: items,
      ),
    );
    notifyListeners();
  }

  bool receiveSupplierDelivery(String orderId) {
    final idx = supplierOrders.indexWhere((o) => o.id == orderId);
    if (idx < 0) return false;

    final order = supplierOrders[idx];
    if (order.status == 'Delivered') return false;

    // 1. Mark as Delivered
    order.status = 'Delivered';

    // 2. Automatically increment on-hand inventory quantities (FR-01)
    for (final orderedItem in order.items) {
      final invIdx = inventory.indexWhere(
        (i) => i.name.toLowerCase().contains(orderedItem.itemName.toLowerCase()) ||
               orderedItem.itemName.toLowerCase().contains(i.name.toLowerCase()),
      );
      if (invIdx >= 0) {
        inventory[invIdx].quantity += orderedItem.quantity;
      }
    }

    notifyListeners();
    return true;
  }
}
