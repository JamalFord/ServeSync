import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_state.dart';

class OrderCartSheet extends StatelessWidget {
  final int initialTableNumber;
  final VoidCallback onOrderSubmitted;

  const OrderCartSheet({
    super.key,
    required this.initialTableNumber,
    required this.onOrderSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final cart = appState.currentCart;
        final tableNumber = appState.selectedTableForOrder ?? initialTableNumber;

        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Grab Bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Header with Table Indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ACTIVE ORDER TICKET',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: AppTheme.primary,
                          ),
                        ),
                        Text(
                          'Table $tableNumber • ${cart.length} Items',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if (cart.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.statusRed),
                        label: const Text(
                          'Clear',
                          style: TextStyle(color: AppTheme.statusRed, fontSize: 13),
                        ),
                        onPressed: () => appState.clearCart(),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Table Selector Dropdown / Chips
                Row(
                  children: [
                    const Text('Assign Table: ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: tableNumber,
                      dropdownColor: AppTheme.surfaceElevated,
                      underline: const SizedBox(),
                      items: appState.tables.map((t) {
                        return DropdownMenuItem<int>(
                          value: t.tableNumber,
                          child: Text('Table ${t.tableNumber} (${t.status.name})'),
                        );
                      }).toList(),
                      onChanged: (newTable) {
                        if (newTable != null) {
                          appState.selectFloorPlanTable(newTable);
                        }
                      },
                    ),
                  ],
                ),

                const Divider(color: AppTheme.border),

                // Cart Items List
                if (cart.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    alignment: Alignment.center,
                    child: const Column(
                      children: [
                        Icon(Icons.shopping_bag_outlined, size: 48, color: AppTheme.textMuted),
                        SizedBox(height: 12),
                        Text(
                          'No items in cart yet',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tap items from the menu to add to this order',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: cart.length,
                      separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 16),
                      itemBuilder: (context, index) {
                        final item = cart[index];
                        return Row(
                          children: [
                            // Quantity Controls
                            Container(
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Row(
                                children: [
                                  InkWell(
                                    onTap: () => appState.decrementCartItem(index),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Icon(Icons.remove, size: 14),
                                    ),
                                  ),
                                  Text(
                                    '${item.quantity}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      final menuItem = appState.menuCatalog.firstWhere((m) => m.id == item.menuItemId);
                                      appState.addToCart(menuItem);
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Icon(Icons.add, size: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Item Name & Modifiers
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  if (item.modifications.isNotEmpty)
                                    Text(
                                      item.modifications,
                                      style: const TextStyle(fontSize: 11, color: AppTheme.primaryLight),
                                    ),
                                ],
                              ),
                            ),

                            // Price
                            Text(
                              '\$${item.totalPrice.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                const Divider(color: AppTheme.border),

                // Calculation Breakdown
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    Text('\$${appState.cartSubtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tax (8.25%)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    Text('\$${appState.cartTax.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Due',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.textPrimary),
                    ),
                    Text(
                      '\$${appState.cartTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        color: AppTheme.primaryLight,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Smart Inventory Auto-Deduction Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.statusGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.statusGreen.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 14, color: AppTheme.statusGreen),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Inventory ingredients will automatically deduct upon kitchen submission.',
                          style: TextStyle(fontSize: 11, color: AppTheme.statusGreen, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Submit Order Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cart.isEmpty ? AppTheme.surfaceHighlight : AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: cart.isEmpty ? 0 : 4,
                    ),
                    onPressed: cart.isEmpty
                        ? null
                        : () {
                            final success = appState.submitOrderToKitchen(tableNumber);
                            if (success) {
                              Navigator.pop(context);
                              onOrderSubmitted();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppTheme.statusGreen,
                                  behavior: SnackBarBehavior.floating,
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle, color: Colors.white),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Order dispatched to Kitchen & Table $tableNumber updated!',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                          },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Send Order to Kitchen (KDS)',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ],
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
}
