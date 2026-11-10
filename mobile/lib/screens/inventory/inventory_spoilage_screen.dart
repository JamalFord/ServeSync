import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/inventory_item.dart';
import '../../models/supplier_order.dart';
import '../../services/app_state.dart';
import '../manage/manage_widgets.dart';

class InventorySpoilageScreen extends StatefulWidget {
  const InventorySpoilageScreen({super.key});

  @override
  State<InventorySpoilageScreen> createState() => _InventorySpoilageScreenState();
}

class _InventorySpoilageScreenState extends State<InventorySpoilageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final inventory = appState.inventory;
        final spoilage = appState.spoilageHistory;
        final lowStockCount = inventory.where((i) => i.isLowStock).length;

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.surface,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.statusGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.inventory_2_rounded, color: AppTheme.statusGreen, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STOCK & FRESHNESS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppTheme.primary,
                      ),
                    ),
                    Text(
                      'Inventory & Spoilage (UC-11)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primary,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('On-Hand Stock'),
                      if (lowStockCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.statusRed,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$lowStockCount Alert',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Spoilage Audit Log'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${spoilage.length}',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Supplier Orders'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${appState.supplierOrders.where((o) => o.status == "Pending").length}',
                          style: TextStyle(color: AppTheme.primaryLight, fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildStockTab(context, appState, inventory),
              _buildSpoilageTab(spoilage),
              _buildSupplierOrdersTab(context, appState),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.remove_circle_outline),
            label: const Text(
              'Log Spoilage',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            onPressed: () => _openLogSpoilageSheet(context, appState),
          ),
        );
      },
    );
  }

  /// FR-3: add an inventory item, or edit one. Changing the quantity of an
  /// existing item is a manual stock adjustment and needs a reason.
  Future<void> _openInventoryItemDialog(BuildContext context, AppState appState, [InventoryItem? item]) async {
    String trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    final name = TextEditingController(text: item?.name ?? '');
    final category = TextEditingController(text: item?.category ?? '');
    final unit = TextEditingController(text: item?.unit ?? '');
    final reorder = TextEditingController(text: item == null ? '' : trim(item.reorderLevel));
    final cost = TextEditingController(text: item == null ? '' : item.unitCost.toStringAsFixed(2));
    final quantity = TextEditingController(text: item == null ? '0' : trim(item.quantity));
    final reason = TextEditingController();

    final saved = await showFormDialog(
      context,
      title: item == null ? 'Add inventory item' : 'Edit ${item.name}',
      subtitle: item == null
          ? null
          : 'Changing the quantity records a manual stock adjustment in the audit log.',
      submitLabel: item == null ? 'Add item' : 'Save changes',
      fields: (_) => [
        FormTextField(label: 'Item name', controller: name, maxLength: 100),
        FormTextField(label: 'Category', controller: category, hint: 'Produce, Meat, Dairy', maxLength: 50),
        FormTextField(label: 'Unit', controller: unit, hint: 'lbs, units, gallons', maxLength: 20),
        FormTextField.decimal(label: 'Reorder level', controller: reorder),
        FormTextField.decimal(label: 'Unit cost (\$)', controller: cost),
        FormTextField.decimal(label: item == null ? 'Opening quantity' : 'Quantity on hand', controller: quantity),
        if (item != null)
          FormTextField(
            label: 'Reason for quantity change (required if the quantity changes)',
            controller: reason,
            hint: 'Stock count, correction',
            maxLength: 80,
          ),
      ],
      onSubmit: () async {
        final reorderValue = double.tryParse(reorder.text.trim());
        final costValue = double.tryParse(cost.text.trim());
        final quantityValue = double.tryParse(quantity.text.trim());
        if (reorderValue == null || costValue == null || quantityValue == null) {
          return 'Reorder level, unit cost and quantity must be numbers.';
        }
        return appState.saveInventoryItem(
          id: item?.id,
          name: name.text,
          category: category.text,
          unit: unit.text,
          reorderLevel: reorderValue,
          unitCost: costValue,
          quantity: quantityValue,
          reason: reason.text,
        );
      },
    );
    if (saved && context.mounted) {
      showMessage(context, item == null ? 'Added ${name.text.trim()} to inventory.' : 'Updated ${name.text.trim()}.');
    }
  }

  Widget _buildStockTab(BuildContext context, AppState appState, List<InventoryItem> items) {
    final canEdit = appState.currentEmployee?.isManager == true;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: items.length + (canEdit ? 1 : 0),
      itemBuilder: (context, rawIndex) {
        if (canEdit && rawIndex == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SUPPLY DATABASE (FR-3)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AppTheme.textSecondary,
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add item', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  onPressed: () => _openInventoryItemDialog(context, appState),
                ),
              ],
            ),
          );
        }
        final item = items[rawIndex - (canEdit ? 1 : 0)];
        final ratio = (item.quantity / (item.reorderLevel * 2)).clamp(0.0, 1.0);
        final isLow = item.isLowStock;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isLow ? AppTheme.statusRed.withOpacity(0.8) : AppTheme.border,
              width: isLow ? 1.5 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.category} • \$${item.unitCost.toStringAsFixed(2)} / ${item.unit}',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item.quantity.toStringAsFixed(1)} ${item.unit}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isLow ? AppTheme.statusRed : AppTheme.statusGreen,
                          ),
                        ),
                        if (isLow)
                          Text(
                            '⚠️ Low Stock',
                            style: TextStyle(fontSize: 11, color: AppTheme.statusRed, fontWeight: FontWeight.w700),
                          )
                        else
                          Text(
                            'Min: ${item.reorderLevel.toStringAsFixed(0)} ${item.unit}',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                    if (canEdit)
                      IconButton(
                        icon: Icon(Icons.edit_outlined, size: 18, color: AppTheme.textSecondary),
                        tooltip: 'Edit item',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openInventoryItemDialog(context, appState, item),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: AppTheme.surfaceElevated,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isLow ? AppTheme.statusRed : AppTheme.statusGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpoilageTab(List<SpoilageRecord> records) {
    if (records.isEmpty) {
      return Center(
        child: Text('No spoilage records logged yet.', style: TextStyle(color: AppTheme.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final rec = records[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppTheme.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      rec.itemName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    Text(
                      '-${rec.quantitySpoiled.toStringAsFixed(1)} ${rec.unit}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppTheme.statusRed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.statusRed.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Reason: ${rec.reason}',
                    style: TextStyle(fontSize: 11, color: AppTheme.statusRed, fontWeight: FontWeight.w600),
                  ),
                ),
                if (rec.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Notes: ${rec.notes}',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
                Divider(color: AppTheme.border, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Stock: ${rec.stockBefore.toStringAsFixed(1)} → ${rec.stockAfter.toStringAsFixed(1)} ${rec.unit}',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    Text(
                      'By: ${rec.recordedByName}',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openLogSpoilageSheet(BuildContext context, AppState appState) {
    String selectedInvId = appState.inventory.first.id;
    double spoiledQty = 1.0;
    String selectedReason = 'Expired / Overripe';
    String notes = '';

    final reasons = [
      'Expired / Overripe',
      'Burned / Prep Error',
      'Dropped / Contaminated',
      'Storage Temperature Failure',
      'Customer Return',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final currentItem = appState.inventory.firstWhere((i) => i.id == selectedInvId);

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'UC-11 COMPLIANCE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                color: AppTheme.primary,
                              ),
                            ),
                            Text(
                              'Record Inventory Spoilage',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Ingredient Dropdown
                    Text('Select Inventory Item', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: DropdownButton<String>(
                        value: selectedInvId,
                        isExpanded: true,
                        dropdownColor: AppTheme.surfaceElevated,
                        underline: const SizedBox(),
                        items: appState.inventory.map((inv) {
                          return DropdownMenuItem<String>(
                            value: inv.id,
                            child: Text('${inv.name} (${inv.quantity.toStringAsFixed(1)} ${inv.unit} available)'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setSheetState(() => selectedInvId = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Quantity Input
                    Text(
                      'Spoiled Quantity (Max: ${currentItem.quantity.toStringAsFixed(1)} ${currentItem.unit})',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      initialValue: '1.0',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        suffixText: currentItem.unit,
                      ),
                      onChanged: (val) {
                        spoiledQty = double.tryParse(val) ?? 1.0;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Reason Dropdown
                    Text('Spoilage Reason', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: DropdownButton<String>(
                        value: selectedReason,
                        isExpanded: true,
                        dropdownColor: AppTheme.surfaceElevated,
                        underline: const SizedBox(),
                        items: reasons.map((r) {
                          return DropdownMenuItem<String>(
                            value: r,
                            child: Text(r),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setSheetState(() => selectedReason = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Notes
                    Text('Notes / Root Cause', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    TextFormField(
                      decoration: const InputDecoration(
                        hintText: 'e.g., Soft spots, refrigerator door left ajar',
                      ),
                      onChanged: (val) => notes = val,
                    ),
                    const SizedBox(height: 20),

                    // Submit Spoilage Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.statusRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          final success = appState.logInventorySpoilage(
                            inventoryId: selectedInvId,
                            quantitySpoiled: spoiledQty,
                            reason: selectedReason,
                            notes: notes,
                          );

                          Navigator.pop(ctx);

                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppTheme.statusRed,
                                content: Text('Spoilage logged for ${currentItem.name} (-$spoiledQty ${currentItem.unit})'),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppTheme.statusRed,
                                content: Text('Failed: Quantity exceeds available on-hand stock!'),
                              ),
                            );
                          }
                        },
                        child: const Text(
                          'Confirm & Deduct Inventory',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSupplierOrdersTab(BuildContext context, AppState appState) {
    final orders = appState.supplierOrders;

    return Column(
      children: [
        // Top Action Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PURCHASING & RECEIVING (UC-05)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppTheme.textSecondary,
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                label: const Text('New Order', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                onPressed: () => _openCreateSupplierOrderSheet(context, appState),
              ),
            ],
          ),
        ),

        // List of Supplier Orders
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_rounded, size: 48, color: AppTheme.textMuted),
                      const SizedBox(height: 8),
                      Text('No supplier purchase orders logged.', style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final isPending = order.status == 'Pending';
                    final statusColor = _orderStatusColor(order.status);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isPending ? AppTheme.statusYellow.withOpacity(0.5) : AppTheme.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    order.id,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: statusColor, width: 0.8),
                                    ),
                                    child: Text(
                                      order.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '\$${order.totalOrderCost.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${order.supplierName} • ${order.category}',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),

                          // Items Ordered
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: order.items.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '• ${item.itemName}',
                                        style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                                      ),
                                      Text(
                                        '${item.quantity} ${item.unit} @ \$${item.unitCost.toStringAsFixed(2)}',
                                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          if (order.notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Notes: ${order.notes}',
                              style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                            ),
                          ],

                          if (isPending) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.statusGreen,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.check_circle_outline, size: 16),
                                label: const Text(
                                  'Receive Delivery & Increment Stock (FR-01)',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                                onPressed: () {
                                  final success = appState.receiveSupplierDelivery(order.id);
                                  if (success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppTheme.statusGreen,
                                        content: Text(
                                          'Received ${order.id}. On-hand inventory automatically increased!',
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                            if (appState.currentEmployee?.isManager == true) ...[
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.statusRed,
                                    side: BorderSide(color: AppTheme.statusRed.withOpacity(0.6)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.cancel_outlined, size: 16),
                                  label: const Text(
                                    'Cancel order',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                  ),
                                  onPressed: () => _cancelSupplierOrder(context, appState, order),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _orderStatusColor(String status) {
    switch (status) {
      case 'Pending':
        return AppTheme.statusYellow;
      case 'Partial':
        return AppTheme.statusBlue;
      case 'Cancelled':
        return AppTheme.textMuted;
      default:
        return AppTheme.statusGreen; // Delivered / Received
    }
  }

  /// UC-05 "Remove Order": only a pending order (nothing received yet) can be cancelled.
  Future<void> _cancelSupplierOrder(BuildContext context, AppState appState, SupplierOrder order) async {
    final ok = await confirmAction(
      context,
      title: 'Cancel ${order.id}?',
      message: 'The order to ${order.supplierName} for \$${order.totalOrderCost.toStringAsFixed(2)} will be cancelled. '
          'No stock will be received from it. This cannot be undone.',
      confirmLabel: 'Cancel order',
      danger: true,
    );
    if (!ok) return;
    final error = await appState.cancelSupplierOrder(order.id);
    if (!context.mounted) return;
    showMessage(context, error ?? '${order.id} cancelled.', error: error != null);
  }

  void _openCreateSupplierOrderSheet(BuildContext context, AppState appState) {
    // Online: the suppliers saved in the cloud (Manage > Suppliers). Offline: the demo list.
    final cloudSuppliers = appState.apiSuppliers;
    final supplierCategories = <String, String>{
      if (cloudSuppliers.isEmpty) ...{
        'Metro Farm Produce Co.': 'Produce',
        'Buckhead Prime Meats': 'Meat',
        'Atlantic Seafood Wholesalers': 'Seafood',
      } else
        for (final s in cloudSuppliers) '${s['supplier_name']}': '${s['product_category'] ?? 'General'}',
    };
    String selectedSupplier = supplierCategories.keys.first;
    String selectedCategory = supplierCategories[selectedSupplier]!;
    String selectedItemName = appState.inventory.first.name;
    double orderQty = 20.0;
    final notesController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Create Purchase Order',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Text('Select Approved Supplier (UC-05)', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedSupplier,
                      isExpanded: true,
                      items: [
                        for (final entry in supplierCategories.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text('${entry.key} (${entry.value})', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() {
                            selectedSupplier = val;
                            selectedCategory = supplierCategories[val] ?? 'General';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    Text('Select Inventory Item to Restock', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedItemName,
                      items: appState.inventory.map((inv) {
                        return DropdownMenuItem(
                          value: inv.name,
                          child: Text('${inv.name} (Current: ${inv.quantity} ${inv.unit})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedItemName = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Quantity to Order', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: orderQty > 5 ? () => setSheetState(() => orderQty -= 5) : null,
                                    color: AppTheme.primary,
                                  ),
                                  Text('${orderQty.toStringAsFixed(0)} units', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () => setSheetState(() => orderQty += 5),
                                    color: AppTheme.primary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Text('Order Notes / Restock Reason', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(hintText: 'e.g. Replenish depleted weekend stock'),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          final invItem = appState.inventory.firstWhere((i) => i.name == selectedItemName);
                          appState.createSupplierOrder(
                            supplierName: selectedSupplier,
                            category: selectedCategory,
                            notes: notesController.text.trim(),
                            items: [
                              SupplierOrderItem(
                                itemName: selectedItemName,
                                quantity: orderQty,
                                unit: invItem.unit,
                                unitCost: invItem.unitCost,
                              ),
                            ],
                          );

                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppTheme.statusGreen,
                              content: Text('Created purchase order for ${orderQty.toStringAsFixed(0)} ${invItem.unit} of $selectedItemName'),
                            ),
                          );
                        },
                        child: const Text('Submit Purchase Order (UC-05)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
