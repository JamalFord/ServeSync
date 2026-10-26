import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/table_model.dart';
import '../../services/app_state.dart';

class FloorPlanScreen extends StatefulWidget {
  final Function(int tableNumber)? onOpenPOS;

  const FloorPlanScreen({super.key, this.onOpenPOS});

  @override
  State<FloorPlanScreen> createState() => _FloorPlanScreenState();
}

class _FloorPlanScreenState extends State<FloorPlanScreen> {
  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final tables = appState.tables;
        final availableCount = tables.where((t) => t.status == TableStatus.available).length;
        final seatedCount = tables.where((t) => t.status == TableStatus.seated).length;
        final orderedCount = tables.where((t) => t.status == TableStatus.ordered).length;
        final checkCount = tables.where((t) => t.status == TableStatus.checkRequested).length;

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: CustomScrollView(
            slivers: [
              // Header Summary Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DINING ROOM FLOOR PLAN',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.0,
                                  color: AppTheme.primary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Live Table Occupancy',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          // Refresh / Firestore sync badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.statusGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Live Sync',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Status Legend Pills
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildLegendPill('Available ($availableCount)', AppTheme.statusGreen),
                            const SizedBox(width: 8),
                            _buildLegendPill('Seated ($seatedCount)', AppTheme.statusYellow),
                            const SizedBox(width: 8),
                            _buildLegendPill('Ordered ($orderedCount)', AppTheme.statusBlue),
                            const SizedBox(width: 8),
                            _buildLegendPill('Check Out ($checkCount)', const Color(0xFFC084FC)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Interactive Grid of Tables
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.15,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final table = tables[index];
                      return _buildTableCard(table);
                    },
                    childCount: tables.length,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegendPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCard(DiningTable table) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (table.status) {
      case TableStatus.available:
        statusColor = AppTheme.statusGreen;
        statusText = 'Available';
        statusIcon = Icons.check_circle_outline;
        break;
      case TableStatus.seated:
        statusColor = AppTheme.statusYellow;
        statusText = 'Seated (${table.guestCount}p)';
        statusIcon = Icons.people_outline;
        break;
      case TableStatus.ordered:
        statusColor = AppTheme.statusBlue;
        statusText = 'Kitchen Prep';
        statusIcon = Icons.soup_kitchen_outlined;
        break;
      case TableStatus.checkRequested:
        statusColor = const Color(0xFFC084FC);
        statusText = 'Check Bill';
        statusIcon = Icons.receipt_long_outlined;
        break;
    }

    return InkWell(
      onTap: () => _showTableActionsSheet(table),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: table.status == TableStatus.available
                ? AppTheme.border
                : statusColor.withOpacity(0.6),
            width: table.status == TableStatus.available ? 1 : 1.5,
          ),
          boxShadow: table.status != TableStatus.available
              ? [
                  BoxShadow(
                    color: statusColor.withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Row: Table Name & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'T-${table.tableNumber}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Middle: Capacity / Server / Guests
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.table_restaurant_outlined, size: 14, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      'Seats ${table.capacity}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                if (table.serverName != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Server: ${table.serverName}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),

            // Bottom Row: Total Bill or Quick Action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (table.billAmount > 0)
                  Text(
                    '\$${table.billAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryLight,
                    ),
                  )
                else
                  Text(
                    table.status == TableStatus.available ? 'Ready' : 'In Service',
                    style: TextStyle(
                      fontSize: 12,
                      color: table.status == TableStatus.available
                          ? AppTheme.statusGreen
                          : AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTableActionsSheet(DiningTable table) {
    final appState = AppState.instance;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sheet Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Table ${table.tableNumber}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Capacity: ${table.capacity} guests • Current Bill: \$${table.billAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  children: [
                    // Quick POS Order Button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.point_of_sale_rounded),
                        label: const Text(
                          'Open POS Order',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          appState.selectFloorPlanTable(table.tableNumber);
                          if (widget.onOpenPOS != null) {
                            widget.onOpenPOS!(table.tableNumber);
                          }
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    if (table.status == TableStatus.available)
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.statusGreen),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.group_add, color: AppTheme.statusGreen),
                          label: const Text(
                            'Seat Party (4)',
                            style: TextStyle(color: AppTheme.statusGreen, fontWeight: FontWeight.w600),
                          ),
                          onPressed: () {
                            appState.seatGuests(table.tableNumber, 4);
                            Navigator.pop(context);
                          },
                        ),
                      )
                    else
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.statusRed),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.cleaning_services, color: AppTheme.statusRed),
                          label: const Text(
                            'Clear & Reset Table',
                            style: TextStyle(color: AppTheme.statusRed, fontWeight: FontWeight.w600),
                          ),
                          onPressed: () {
                            appState.clearTable(table.tableNumber);
                            Navigator.pop(context);
                          },
                        ),
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
}
