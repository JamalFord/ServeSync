import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/menu_item.dart';
import '../../models/table_model.dart';
import '../../services/app_state.dart';
import 'order_cart_sheet.dart';

class QuickPOSScreen extends StatefulWidget {
  final int defaultTableNumber;
  final VoidCallback? onNavigateToKDS;

  const QuickPOSScreen({
    super.key,
    this.defaultTableNumber = 1,
    this.onNavigateToKDS,
  });

  @override
  State<QuickPOSScreen> createState() => _QuickPOSScreenState();
}

class _QuickPOSScreenState extends State<QuickPOSScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';

  final List<String> _categories = [
    'All',
    'Appetizers',
    'Entrees',
    'Beverages',
    'Desserts',
  ];

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final catalog = appState.menuCatalog;
        final currentTable = appState.selectedTableForOrder ?? widget.defaultTableNumber;
        final cartCount = appState.currentCart.fold(0, (sum, i) => sum + i.quantity);

        final filteredItems = catalog.where((item) {
          final matchesCategory = _selectedCategory == 'All' || item.category == _selectedCategory;
          final matchesSearch = item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              item.description.toLowerCase().contains(_searchQuery.toLowerCase());
          return matchesCategory && matchesSearch;
        }).toList();

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  // App Bar / Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'POINT OF SALE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Table $currentTable Ticket',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              // Table Switcher Pill
                              InkWell(
                                onTap: () => _openTablePicker(appState),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceElevated,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: AppTheme.primaryLight.withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.table_restaurant, size: 14, color: AppTheme.primaryLight),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Table $currentTable',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: AppTheme.primaryLight,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Search Bar
                          TextField(
                            decoration: const InputDecoration(
                              hintText: 'Search dishes, drinks, ingredients...',
                              prefixIcon: Icon(Icons.search, color: AppTheme.textMuted),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val),
                          ),
                          const SizedBox(height: 12),

                          // Category Pills
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _categories.map((cat) {
                                final isSelected = _selectedCategory == cat;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ChoiceChip(
                                    label: Text(cat),
                                    selected: isSelected,
                                    selectedColor: AppTheme.primary,
                                    backgroundColor: AppTheme.surfaceElevated,
                                    labelStyle: TextStyle(
                                      color: isSelected ? Colors.white : AppTheme.textSecondary,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide(
                                        color: isSelected ? AppTheme.primary : AppTheme.border,
                                      ),
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() => _selectedCategory = cat);
                                      }
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Menu Items Grid
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.85,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = filteredItems[index];
                          return _buildMenuItemCard(item, appState);
                        },
                        childCount: filteredItems.length,
                      ),
                    ),
                  ),
                ],
              ),

              // Floating Cart Bottom Bar
              if (cartCount > 0)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: InkWell(
                    onTap: () => _openCartSheet(currentTable),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.primaryLight],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: AppTheme.primaryGlow,
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$cartCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'View Ticket',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                '\$${appState.cartTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuItemCard(MenuItem item, AppState appState) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emoji / Icon & Price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  item.iconEmoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              Text(
                '\$${item.price.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppTheme.primaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Title
          Text(
            item.name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),

          // Description
          Expanded(
            child: Text(
              item.description,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Add to Order Action
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.surfaceElevated,
                foregroundColor: AppTheme.textPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppTheme.border),
                ),
              ),
              icon: const Icon(Icons.add, size: 16, color: AppTheme.primary),
              label: const Text(
                'Add Item',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              onPressed: () {
                appState.addToCart(item);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(milliseconds: 600),
                    backgroundColor: AppTheme.surfaceElevated,
                    behavior: SnackBarBehavior.floating,
                    content: Text(
                      'Added ${item.name}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openTablePicker(AppState appState) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Order Table'),
          content: SizedBox(
            width: double.maxFinite,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: appState.tables.map((t) {
                return ActionChip(
                  label: Text('Table ${t.tableNumber}'),
                  avatar: Icon(
                    Icons.circle,
                    size: 10,
                    color: t.status == TableStatus.available ? AppTheme.statusGreen : AppTheme.statusYellow,
                  ),
                  onPressed: () {
                    appState.selectFloorPlanTable(t.tableNumber);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _openCartSheet(int currentTable) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return OrderCartSheet(
          initialTableNumber: currentTable,
          onOrderSubmitted: () {
            if (widget.onNavigateToKDS != null) {
              widget.onNavigateToKDS!();
            }
          },
        );
      },
    );
  }
}
