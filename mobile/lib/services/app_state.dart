import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
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
  }

  final _uuid = const Uuid();

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

  // ServeSync REST API (Railway + MySQL)
  final ApiClient api = ApiClient();

  /// True while the current employee is signed in through the cloud API.
  /// False means offline demo mode (local seed data only).
  bool isBackendOnline = false;

  /// Last sync warning to surface in the UI (null when everything is in sync).
  String? backendNotice;

  static const _tokenPrefsKey = 'servesync_api_token';
  final Map<String, int> _apiInventoryIds = {}; // local inventory id -> DB inventory_id
  final Map<String, int> _apiPurchaseOrderIds = {}; // local PO id -> DB order_id
  final Map<String, List<Map<String, dynamic>>> _apiPoLines = {}; // local PO id -> DB order lines
  final Map<String, Map<String, dynamic>> _apiSuppliersByName = {}; // supplier_name -> DB row
  final Map<int, List<int>> _apiOpenOrderIdsByTable = {}; // table number -> open DB order_ids (FR-9)

  // Kitchen tickets are read from the API every few seconds while signed in to the cloud,
  // so every device shows the same kitchen queue.
  static const Duration _kitchenPollInterval = Duration(seconds: 5);
  Timer? _kitchenTimer;
  final Set<String> _unsyncedTicketIds = {}; // tickets created here that the API has not saved (yet)

  // --------------------------------------------------------------------------
  // Seed Data Initializer
  // --------------------------------------------------------------------------
  void _initSeedData() {
    // 1. Employees — Group 1 team members (Sprint 3 roster).
    // Names, roles and PINs must match the backend seeds in backend/server.py
    // and database/seed_*.py so cloud and offline logins behave the same.
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
        name: 'Kristian Napier',
        role: 'Manager',
        pin: '2345',
        hourlyRate: 22.50,
        isClockedIn: true,
        clockInTime: DateTime.now().subtract(const Duration(hours: 4, minutes: 15)),
      ),
      Employee(
        id: 'emp_03',
        name: 'Jamal Ford',
        role: 'Administrator',
        pin: '3456',
        hourlyRate: 16.50,
        isClockedIn: false,
      ),
      Employee(
        id: 'emp_04',
        name: 'Sneha Patel',
        role: 'FOH Staff',
        pin: '4567',
        hourlyRate: 16.50,
        isClockedIn: false,
      ),
      Employee(
        id: 'emp_05',
        name: 'Mason Mathias',
        role: 'FOH Staff',
        pin: '5678',
        hourlyRate: 16.50,
        isClockedIn: false,
      ),
    ]);

    // Default active user is Manager Kristian
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
        serverName: 'Sneha Patel',
        seatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
      DiningTable(tableNumber: 4, capacity: 6, status: TableStatus.available),
      DiningTable(
        tableNumber: 5,
        capacity: 4,
        status: TableStatus.checkRequested,
        guestCount: 2,
        serverName: 'Mason Mathias',
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
        recordedByName: 'Kristian Napier',
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
    if (isBackendOnline) {
      unawaited(_toggleShiftOnBackend(currentEmployee!));
      return;
    }
    if (currentEmployee!.isClockedIn) {
      currentEmployee!.isClockedIn = false;
      currentEmployee!.clockInTime = null;
    } else {
      currentEmployee!.isClockedIn = true;
      currentEmployee!.clockInTime = DateTime.now();
    }
    notifyListeners();
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
  }

  void clearTable(int tableNumber) {
    final table = tables.firstWhere((t) => t.tableNumber == tableNumber);
    table.status = TableStatus.available;
    table.guestCount = 0;
    table.billAmount = 0.0;
    table.activeOrderId = null;
    table.seatedAt = null;
    notifyListeners();

    // Clearing the table closes its orders in MySQL (FR-9 "complete order").
    final openOrderIds = _apiOpenOrderIdsByTable.remove(tableNumber) ?? const <int>[];
    if (isBackendOnline && openOrderIds.isNotEmpty) {
      unawaited(_completeOrdersOnBackend(openOrderIds));
    }
  }

  Future<void> _completeOrdersOnBackend(List<int> orderIds) async {
    for (final id in orderIds) {
      try {
        await api.completeOrder(id);
      } on ApiException catch (e) {
        // 409 = already Completed or Cancelled on the server: nothing left to do.
        if (e.status != 409) {
          backendNotice = 'Order #$id not closed in the cloud: ${e.message}';
          notifyListeners();
        }
      }
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

    // 5. Store the order in MySQL (FR-9). The server prices the lines from its own menu,
    // deducts ingredients and logs the usage; _runBackendSync then re-reads inventory, so the
    // local deduction above is only instant feedback and is replaced by the server's figures.
    if (isBackendOnline) {
      final lines = [
        for (final item in currentCart)
          {
            'name': item.name,
            'quantity': item.quantity,
            'modifications': _orderLineNote(item),
          },
      ];
      // The ticket above is shown at once; when the API has saved the order it is replaced
      // by the server's ticket, which every other device also receives.
      _unsyncedTicketIds.add(ticketId);
      unawaited(_runBackendSync('Order', () async {
        final saved = await api.createOrder({'table_number': tableNumber, 'items': lines});
        final dbOrderId = saved['order_id'];
        if (dbOrderId is num) {
          _apiOpenOrderIdsByTable.putIfAbsent(tableNumber, () => <int>[]).add(dbOrderId.toInt());
        }
        _unsyncedTicketIds.remove(ticketId);
      }));
    }

    // 6. Clear Cart
    currentCart.clear();
    notifyListeners();


    return true;
  }

  /// Seat number plus any modifications, cut to the 255 characters the database column holds.
  static String _orderLineNote(OrderItem item) {
    final mods = item.modifications.trim();
    final seat = item.seatNumber == 0 ? 'Shared' : 'Seat ${item.seatNumber}'; // seat 0 = shared by the table
    final note = mods.isEmpty ? seat : '$seat: $mods';
    return note.length > 255 ? note.substring(0, 255) : note;
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
      final dbOrderId = ticket.dbOrderId;
      if (isBackendOnline && dbOrderId != null) {
        unawaited(_syncKitchenStatus(dbOrderId, ticket.status));
      }
    }
  }

  Future<void> _syncKitchenStatus(int dbOrderId, TicketStatus status) async {
    const names = {
      TicketStatus.inPrep: 'In Prep',
      TicketStatus.ready: 'Ready',
      TicketStatus.served: 'Served',
    };
    final name = names[status];
    if (name == null) return;
    try {
      await api.setKitchenStatus(dbOrderId, name);
      backendNotice = null;
    } on ApiException catch (e) {
      backendNotice = 'Kitchen ticket not updated in the cloud: ${e.message}';
    }
    await refreshKitchenTickets();
  }

  /// Reads the shared kitchen queue from the API (FR-9). Tickets created on this device that
  /// the API has not saved yet are kept at the top.
  Future<void> refreshKitchenTickets() async {
    if (!isBackendOnline) return;
    final List<Map<String, dynamic>> rows;
    try {
      rows = await api.kitchenTickets();
    } on ApiException catch (e) {
      debugPrint('Kitchen tickets not refreshed: ${e.message}');
      return; // keep what is on screen
    }
    if (!isBackendOnline) return;
    final next = [
      ...kdsTickets.where((t) => _unsyncedTicketIds.contains(t.id)),
      ...rows.map(_ticketFromApi),
    ];
    String signature(List<KDSTicket> list) =>
        list.map((t) => '${t.id}:${t.status.index}:${t.items.length}').join('|');
    if (signature(next) == signature(kdsTickets)) return;
    kdsTickets
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void _startKitchenSync() {
    _kitchenTimer?.cancel();
    _kitchenTimer = Timer.periodic(_kitchenPollInterval, (_) => unawaited(refreshKitchenTickets()));
  }

  void _stopKitchenSync() {
    _kitchenTimer?.cancel();
    _kitchenTimer = null;
  }

  static KDSTicket _ticketFromApi(Map<String, dynamic> row) {
    final dbId = (row['order_id'] as num).toInt();
    final status = switch (row['kitchen_status']?.toString()) {
      'In Prep' => TicketStatus.inPrep,
      'Ready' => TicketStatus.ready,
      'Served' => TicketStatus.served,
      _ => TicketStatus.newOrder,
    };
    final lines = ((row['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map));
    // An order from a delivery platform has no table; it is labelled with the platform instead.
    final source = row['source']?.toString() ?? 'Dine-in';
    final isDelivery = source != 'Dine-in' || row['table_number'] == null;
    return KDSTicket(
      id: 'KDS-$dbId',
      orderId: 'ORD-$dbId',
      dbOrderId: dbId,
      tableNumber: (row['table_number'] as num?)?.toInt() ?? 0,
      label: isDelivery ? source.toUpperCase() : null,
      serverName: isDelivery
          ? (row['customer_name']?.toString() ?? 'Delivery customer')
          : (row['server_name']?.toString() ?? 'Server'),
      status: status,
      orderTime: _parseServerTime(row['order_time']),
      items: [
        for (final line in lines) _ticketItemFromApi(line),
      ],
    );
  }

  /// Order lines carry the seat as a note: "Seat 2", "Shared", or "Seat 2: no onions".
  static KDSTicketItem _ticketItemFromApi(Map<String, dynamic> line) {
    final note = line['modifications']?.toString() ?? '';
    final match = RegExp(r'^(?:Seat (\d+)|Shared)(?:: (.*))?$', dotAll: true).firstMatch(note);
    return KDSTicketItem(
      name: line['item_name']?.toString() ?? '',
      quantity: (line['quantity'] as num?)?.toInt() ?? 1,
      seatNumber: match == null ? 1 : int.tryParse(match.group(1) ?? '') ?? 0,
      modifications: match == null ? note : (match.group(2) ?? ''),
    );
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


    final apiInventoryId = _apiInventoryIds[item.id];
    if (isBackendOnline && apiInventoryId != null) {
      unawaited(_runBackendSync('Spoilage log', () => api.recordSpoilage({
            'inventory_id': apiInventoryId,
            'quantity': quantitySpoiled,
            'reason': reason,
            'notes': notes,
            'request_id': requestId, // idempotency key: safe to retry
          })));
    }
    return true;
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

    if (isBackendOnline) {
      final supplier = _apiSuppliersByName[supplierName];
      final lines = <Map<String, dynamic>>[];
      for (final it in items) {
        final local = _findInventoryByName(it.itemName);
        final dbId = local == null ? null : _apiInventoryIds[local.id];
        if (dbId == null) {
          lines.clear();
          break;
        }
        lines.add({'inventory_id': dbId, 'quantity_ordered': it.quantity, 'unit_cost': it.unitCost});
      }
      if (supplier == null || lines.isEmpty) {
        backendNotice = 'Purchase order kept on this device only: supplier or item is not in the cloud catalog.';
        notifyListeners();
      } else {
        unawaited(_runBackendSync('Purchase order', () => api.createPurchaseOrder({
              'supplier_id': supplier['supplier_id'],
              'items': lines,
            })));
      }
    }
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

    final dbOrderId = _apiPurchaseOrderIds[orderId];
    if (isBackendOnline && dbOrderId != null) {
      final received = [
        for (final line in _apiPoLines[orderId] ?? const <Map<String, dynamic>>[])
          if (_num(line['quantity_ordered']) - _num(line['quantity_received']) > 0)
            {
              'item_id': line['item_id'],
              'quantity_received': _num(line['quantity_ordered']) - _num(line['quantity_received']),
            },
      ];
      if (received.isNotEmpty) {
        unawaited(_runBackendSync('Delivery receipt', () => api.receiveDelivery(dbOrderId, {
              'request_id': 'RCV-${_uuid.v4()}',
              'received_items': received,
              'notes': 'Received in full from ServeSync app',
            })));
      }
    }
    return true;
  }

  /// Cancels a pending purchase order (UC-05 "Remove Order").
  /// Returns null on success, or a message to show the user.
  Future<String?> cancelSupplierOrder(String orderId) async {
    final idx = supplierOrders.indexWhere((o) => o.id == orderId);
    if (idx < 0) return 'Purchase order not found.';
    if (supplierOrders[idx].status != 'Pending') return 'Only a pending purchase order can be cancelled.';
    final dbOrderId = _apiPurchaseOrderIds[orderId];
    if (isBackendOnline && dbOrderId != null) {
      try {
        await api.cancelPurchaseOrder(dbOrderId);
      } on ApiException catch (e) {
        return e.message;
      }
      await refreshFromBackend();
      return null;
    }
    supplierOrders[idx].status = 'Cancelled';
    notifyListeners();
    return null;
  }

  /// Database id of a local inventory item, or null in offline demo mode.
  int? apiInventoryIdFor(String localId) => _apiInventoryIds[localId];

  /// Database row of a supplier by name (keys: supplier_id, supplier_name, contact_person,
  /// phone_number, email, product_category), or null when not loaded from the cloud.
  Map<String, dynamic>? apiSupplierByName(String name) => _apiSuppliersByName[name];

  /// Suppliers loaded from the cloud, sorted by name (empty in offline demo mode).
  List<Map<String, dynamic>> get apiSuppliers =>
      _apiSuppliersByName.values.toList()..sort((a, b) => '${a['supplier_name']}'.compareTo('${b['supplier_name']}'));

  /// Adds (id == null) or edits an inventory item (FR-3). Changing [quantity] on an existing
  /// item is a manual stock adjustment and needs a [reason]. Returns null on success, or a
  /// message to show the user.
  Future<String?> saveInventoryItem({
    String? id,
    required String name,
    required String category,
    required String unit,
    required double reorderLevel,
    required double unitCost,
    double? quantity,
    String reason = '',
  }) async {
    final existingIdx = id == null ? -1 : inventory.indexWhere((i) => i.id == id);
    if (id != null && existingIdx < 0) return 'Inventory item not found.';
    if (name.trim().isEmpty || category.trim().isEmpty || unit.trim().isEmpty) {
      return 'Name, category and unit are required.';
    }
    if (reorderLevel < 0 || unitCost < 0 || (quantity != null && quantity < 0)) {
      return 'Quantities and costs cannot be negative.';
    }
    final existing = existingIdx >= 0 ? inventory[existingIdx] : null;
    final quantityChanged = existing != null && quantity != null && (quantity - existing.quantity).abs() > 0.004;
    if (quantityChanged && reason.trim().isEmpty) return 'A reason is required to adjust the stock quantity.';

    if (isBackendOnline) {
      final body = <String, dynamic>{
        'item_name': name.trim(),
        'category': category.trim(),
        'unit': unit.trim(),
        'reorder_level': reorderLevel,
        'unit_cost': unitCost,
        if (existing == null) 'quantity': quantity ?? 0,
        if (quantityChanged) 'quantity': quantity,
        if (quantityChanged) 'reason': reason.trim(),
      };
      try {
        final dbId = existing == null ? null : _apiInventoryIds[existing.id];
        if (existing == null) {
          await api.createInventoryItem(body);
        } else if (dbId != null) {
          await api.updateInventoryItem(dbId, body);
        } else {
          return 'This item is not in the cloud catalog.';
        }
      } on ApiException catch (e) {
        return e.message;
      }
      await refreshFromBackend();
      return null;
    }

    final item = InventoryItem(
      id: existing?.id ?? 'inv_${_uuid.v4().substring(0, 8)}',
      name: name.trim(),
      category: category.trim(),
      quantity: quantity ?? existing?.quantity ?? 0,
      unit: unit.trim(),
      reorderLevel: reorderLevel,
      unitCost: unitCost,
    );
    if (existing == null) {
      inventory.add(item);
    } else {
      inventory[existingIdx] = item;
    }
    notifyListeners();
    return null;
  }

  // --------------------------------------------------------------------------
  // Cloud backend (Railway REST API + MySQL)
  //
  // Online: login, shifts, inventory, spoilage and purchase orders go through
  // the API, and the server's data replaces the local seed data. POS orders are
  // also stored in MySQL (POST /orders on send, /orders/{id}/complete when the
  // table is cleared); the server deducts the ingredients each order uses.
  // Offline (API unreachable or its database is down): the app keeps working
  // on local seed data so demos never break.
  // Kitchen tickets are read from the API every few seconds, so all devices
  // show the same queue. The floor plan and the menu shown on the POS are held
  // on the device; the server keeps its own menu and table list and matches
  // order lines to it by item name.
  // --------------------------------------------------------------------------

  /// True when the last sign-in was refused because this employee is still signed in on another
  /// device. The login screen then offers to sign in here instead.
  bool signInBlockedByOtherSession = false;

  /// Signs in with a 4-digit PIN. Returns null on success, or an error message.
  /// With [takeOver], a session the employee left open on another device is ended first.
  Future<String?> signInWithPin(String pin, {bool takeOver = false}) async {
    signInBlockedByOtherSession = false;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('Local preferences unavailable: $e');
    }

    // The API allows one session per employee. Close a session this device left
    // open (page refresh, app killed) so the employee is not locked out for 12h.
    final staleToken = prefs?.getString(_tokenPrefsKey);
    if (staleToken != null) {
      api.token = staleToken;
      try {
        await api.logout();
      } catch (_) {}
      api.token = null;
      await prefs?.remove(_tokenPrefsKey);
    }

    try {
      final res = await api.login(pin, takeOver: takeOver);
      api.token = res['token'] as String?;
      if (api.token != null) await prefs?.setString(_tokenPrefsKey, api.token!);
      _applyApiUser(
        Map<String, dynamic>.from(res['user'] as Map),
        Map<String, dynamic>.from((res['shift_status'] ?? const {}) as Map),
        pin,
      );
      isBackendOnline = true;
      backendNotice = null;
      notifyListeners();
      unawaited(refreshFromBackend());
      _startKitchenSync();
      return null;
    } on ApiException catch (e) {
      // 401 wrong PIN, 409 already signed in elsewhere, 429 rate limited:
      // the server is authoritative, so report it instead of falling back.
      if (!e.isUnavailable) {
        signInBlockedByOtherSession = e.status == 409;
        return e.message;
      }

      isBackendOnline = false;
      if (authenticateWithPin(pin)) {
        backendNotice = 'Offline demo mode: ServeSync cloud is unavailable (${e.message})';
        notifyListeners();
        return null;
      }
      return 'Invalid Access PIN.';
    }
  }

  /// Ends the API session. Per client requirement this does NOT end the shift.
  Future<void> signOut() async {
    final token = api.token;
    api.token = null;
    isBackendOnline = false;
    _stopKitchenSync();
    _unsyncedTicketIds.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (token != null) {
        api.token = token;
        try {
          await api.logout();
        } finally {
          api.token = null;
        }
      }
      await prefs.remove(_tokenPrefsKey);
    } catch (e) {
      debugPrint('Logout sync failed: $e');
    }
    notifyListeners();
  }

  /// Pulls inventory, spoilage history, purchase orders and the menu from the API.
  Future<void> refreshFromBackend() async {
    if (!isBackendOnline) return;
    await _refreshMenu();
    try {
      final results = await Future.wait([
        api.inventory(),
        api.spoilageHistory(),
        api.suppliers(),
        api.purchaseOrders(),
      ]);
      _mergeInventory(results[0]);
      _replaceSpoilage(results[1]);
      _apiSuppliersByName
        ..clear()
        ..addEntries(results[2].map((s) => MapEntry(s['supplier_name'].toString(), s)));
      _replacePurchaseOrders(results[3]);
    } on ApiException catch (e) {
      backendNotice = 'Cloud sync failed: ${e.message}';
    }
    notifyListeners();
    await refreshKitchenTickets();
  }

  /// Loads the menu that managers maintain in Manage > Menu & Prices (FR-13, FR-14), so the POS
  /// always sells the current items at the current prices. Items that are on the built-in demo
  /// menu keep their icon and recipe; items added later get an icon for their category.
  Future<void> _refreshMenu() async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await api.menu();
    } on ApiException catch (e) {
      debugPrint('Menu not refreshed: ${e.message}');
      return; // keep the menu already on screen
    }
    if (rows.isEmpty) return;
    _builtInMenu ??= {for (final m in menuCatalog) m.name.toLowerCase(): m};
    const icons = {
      'appetizers': '🍟', 'entrees': '🍽️', 'beverages': '🥤', 'desserts': '🍰', 'salads': '🥗',
      'sides': '🥔', 'soups': '🍲', 'breakfast': '🍳', 'pizza': '🍕', 'pasta': '🍝',
    };
    final next = <MenuItem>[];
    for (final row in rows) {
      final name = row['item_name']?.toString() ?? 'Item';
      final builtIn = _builtInMenu![name.toLowerCase()];
      final category = row['category']?.toString() ?? 'Entrees';
      next.add(MenuItem(
        id: builtIn?.id ?? 'db_menu_${row['menu_item_id']}',
        name: name,
        category: category,
        price: _num(row['price']),
        description: row['description']?.toString() ?? '',
        isAvailable: row['available'] == true || row['available'] == 1 || row['available'] == '1',
        iconEmoji: builtIn?.iconEmoji ?? icons[category.toLowerCase()] ?? '🍽️',
        inventoryIngredients: builtIn?.inventoryIngredients ?? const {},
      ));
    }
    menuCatalog
      ..clear()
      ..addAll(next);
    // Drop cart lines whose item was removed from the menu or is no longer available.
    currentCart.removeWhere((line) => !menuCatalog.any((m) => m.id == line.menuItemId && m.isAvailable));
    notifyListeners();
  }

  Map<String, MenuItem>? _builtInMenu; // demo menu by lower-case name, captured before the first cloud load

  Future<void> _runBackendSync(String label, Future<dynamic> Function() call) async {
    try {
      await call();
      backendNotice = null;
    } on ApiException catch (e) {
      backendNotice = '$label not saved to the cloud: ${e.message}';
    }
    // Re-read server truth either way so local state never drifts from MySQL.
    await refreshFromBackend();
  }

  Future<void> _toggleShiftOnBackend(Employee emp) async {
    try {
      final status = emp.isClockedIn ? await api.clockOut() : await api.clockIn();
      _applyShiftStatus(emp, status);
      backendNotice = null;
    } on ApiException catch (e) {
      backendNotice = 'Shift update failed: ${e.message}';
      try {
        _applyShiftStatus(emp, await api.shiftStatus());
      } catch (_) {}
    }
    notifyListeners();
  }

  void _applyApiUser(Map<String, dynamic> user, Map<String, dynamic> shift, String pin) {
    final name = user['full_name']?.toString() ?? 'Employee';
    final idx = employees.indexWhere((e) => e.name.toLowerCase() == name.toLowerCase());
    final emp = Employee(
      id: 'db_${user['user_id']}',
      name: name,
      role: user['role']?.toString() ?? 'FOH Staff',
      pin: pin,
      // The API does not expose wages yet; it bills new shifts at $15.00/hr.
      hourlyRate: idx >= 0 ? employees[idx].hourlyRate : 15.00,
    );
    _applyShiftStatus(emp, shift);
    if (idx >= 0) {
      employees[idx] = emp;
    } else {
      employees.add(emp);
    }
    currentEmployee = emp;
  }

  void _applyShiftStatus(Employee emp, Map<String, dynamic> status) {
    emp.isClockedIn = status['is_clocked_in'] == true;
    emp.clockInTime = emp.isClockedIn ? _parseServerTime(status['clock_in_time']) ?? DateTime.now() : null;
  }

  InventoryItem? _findInventoryByName(String name) {
    final lower = name.trim().toLowerCase();
    for (final i in inventory) {
      if (i.name.toLowerCase() == lower) return i;
    }
    return null;
  }

  InventoryItem? _findInventoryByDbId(int dbId, Map<String, int> ids) {
    for (final i in inventory) {
      if (ids[i.id] == dbId) return i;
    }
    return null;
  }

  void _mergeInventory(List<Map<String, dynamic>> rows) {
    final previousIds = Map<String, int>.from(_apiInventoryIds);
    _apiInventoryIds.clear();
    for (final row in rows) {
      final dbId = (row['inventory_id'] as num).toInt();
      final updated = _parseServerTime(row['last_updated']) ?? DateTime.now();
      // Keep local ids (menu recipes reference them) and match rows by name.
      final local = _findInventoryByName(row['item_name']?.toString() ?? '') ??
          _findInventoryByDbId(dbId, previousIds);
      if (local != null) {
        // Replace the item so edits made in the cloud (name, reorder level, cost) show up too.
        inventory[inventory.indexOf(local)] = InventoryItem(
          id: local.id,
          name: row['item_name']?.toString() ?? local.name,
          category: row['category']?.toString() ?? local.category,
          quantity: _num(row['quantity']),
          unit: row['unit']?.toString() ?? local.unit,
          reorderLevel: _num(row['reorder_level']),
          unitCost: _num(row['unit_cost']),
          lastUpdated: updated,
        );
        _apiInventoryIds[local.id] = dbId;
      } else {
        final item = InventoryItem(
          id: 'db_inv_$dbId',
          name: row['item_name']?.toString() ?? 'Ingredient',
          category: row['category']?.toString() ?? 'General',
          quantity: _num(row['quantity']),
          unit: row['unit']?.toString() ?? 'units',
          reorderLevel: _num(row['reorder_level']),
          unitCost: _num(row['unit_cost']),
          lastUpdated: updated,
        );
        inventory.add(item);
        _apiInventoryIds[item.id] = dbId;
      }
    }
    // MySQL is the source of truth: drop seed items the cloud doesn't track.
    // (Menu recipes referencing them are skipped by submitOrderToKitchen.)
    inventory.removeWhere((i) => !_apiInventoryIds.containsKey(i.id));
  }

  void _replaceSpoilage(List<Map<String, dynamic>> rows) {
    final localIdByDbId = {for (final e in _apiInventoryIds.entries) e.value: e.key};
    spoilageHistory
      ..clear()
      ..addAll(rows.map((r) => SpoilageRecord(
            id: 'SPL-${r['spoilage_id']}',
            inventoryId: localIdByDbId[(r['inventory_id'] as num).toInt()] ?? '',
            itemName: r['item_name']?.toString() ?? '',
            quantitySpoiled: _num(r['quantity_spoiled']),
            unit: r['unit']?.toString() ?? 'lbs',
            reason: r['reason']?.toString() ?? '',
            notes: r['notes']?.toString() ?? '',
            recordedByName: r['recorded_by_name']?.toString() ?? 'Staff',
            occurredAt: _parseServerTime(r['occurred_at']) ?? DateTime.now(),
            stockBefore: _num(r['stock_before']),
            stockAfter: _num(r['stock_after']),
            requestId: r['request_id']?.toString() ?? '',
          )));
  }

  void _replacePurchaseOrders(List<Map<String, dynamic>> rows) {
    _apiPurchaseOrderIds.clear();
    _apiPoLines.clear();
    supplierOrders.clear();
    for (final r in rows) {
      final dbId = (r['order_id'] as num).toInt();
      final id = 'PO-$dbId';
      final lines = ((r['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final orderDate = _parseServerTime(r['order_date']) ?? DateTime.now();
      final supplierName = r['supplier_name']?.toString() ?? 'Supplier';
      _apiPurchaseOrderIds[id] = dbId;
      _apiPoLines[id] = lines;
      supplierOrders.add(SupplierOrder(
        id: id,
        supplierName: supplierName,
        category: _apiSuppliersByName[supplierName]?['product_category']?.toString() ?? 'General',
        orderDate: orderDate,
        expectedDeliveryDate: orderDate.add(const Duration(days: 2)),
        // The app's UI uses 'Delivered' where the database says 'Received'.
        status: r['status'] == 'Received' ? 'Delivered' : (r['status']?.toString() ?? 'Pending'),
        notes: 'Created by ${r['created_by_name'] ?? 'staff'}',
        items: lines
            .map((l) => SupplierOrderItem(
                  itemName: l['item_name']?.toString() ?? '',
                  quantity: _num(l['quantity_ordered']),
                  unit: l['unit']?.toString() ?? 'units',
                  unitCost: _num(l['unit_cost']),
                ))
            .toList(),
      ));
    }
  }

  /// The API sends DECIMAL columns as strings ("38.50").
  static double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

  /// Server timestamps are naive UTC ("2026-11-08 03:54:17" or ISO "T" form).
  static DateTime? _parseServerTime(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim().replaceFirst(' ', 'T');
    final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
    return DateTime.tryParse(hasZone ? s : '${s}Z')?.toLocal();
  }
}
