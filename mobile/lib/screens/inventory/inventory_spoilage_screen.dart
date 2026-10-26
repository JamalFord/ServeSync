import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/inventory_item.dart';
import '../../services/app_state.dart';

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
    _tabController = TabController(length: 2, vsync: this);
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
                  child: const Icon(Icons.inventory_2_rounded, color: AppTheme.statusGreen, size: 20),
                ),
                const SizedBox(width: 10),
                const Column(
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
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
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
              _buildStockTab(inventory),
              _buildSpoilageTab(spoilage),
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

  Widget _buildStockTab(List<InventoryItem> items) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.category} • \$${item.unitCost.toStringAsFixed(2)} / ${item.unit}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
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
                          const Text(
                            '⚠️ Low Stock',
                            style: TextStyle(fontSize: 11, color: AppTheme.statusRed, fontWeight: FontWeight.w700),
                          )
                        else
                          Text(
                            'Min: ${item.reorderLevel.toStringAsFixed(0)} ${item.unit}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                      ],
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
      return const Center(
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
            side: const BorderSide(color: AppTheme.border),
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
                      style: const TextStyle(
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
                    style: const TextStyle(fontSize: 11, color: AppTheme.statusRed, fontWeight: FontWeight.w600),
                  ),
                ),
                if (rec.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Notes: ${rec.notes}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
                const Divider(color: AppTheme.border, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Stock: ${rec.stockBefore.toStringAsFixed(1)} → ${rec.stockAfter.toStringAsFixed(1)} ${rec.unit}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    Text(
                      'By: ${rec.recordedByName}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
                        const Column(
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
                    const Text('Select Inventory Item', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
                    const Text('Spoilage Reason', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
                    const Text('Notes / Root Cause', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
                              const SnackBar(
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
}
