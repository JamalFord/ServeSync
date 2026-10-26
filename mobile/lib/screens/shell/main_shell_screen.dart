import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/kds_ticket.dart';
import '../../services/app_state.dart';
import '../floor_plan/floor_plan_screen.dart';
import '../pos/quick_pos_screen.dart';
import '../kds/kds_screen.dart';
import '../inventory/inventory_spoilage_screen.dart';
import '../shifts/shifts_screen.dart';
import '../auth/pin_keypad_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;

  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final currentEmp = appState.currentEmployee;
        final kdsCount = appState.kdsTickets.where((t) => t.status != TicketStatus.served).length;
        final lowStockCount = appState.inventory.where((i) => i.isLowStock).length;

        final screens = [
          FloorPlanScreen(
            onOpenPOS: (tableNum) {
              appState.selectFloorPlanTable(tableNum);
              _navigateToTab(1); // switch to POS tab
            },
          ),
          QuickPOSScreen(
            defaultTableNumber: appState.selectedTableForOrder ?? 1,
            onNavigateToKDS: () {
              _navigateToTab(2); // switch to KDS tab
            },
          ),
          const KDSScreen(),
          const InventorySpoilageScreen(),
          ShiftsScreen(
            onSwitchUser: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const PinKeypadScreen()),
              );
            },
          ),
        ];

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.surface,
            elevation: 0,
            leadingWidth: 44,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: CircleAvatar(
                backgroundColor: AppTheme.surfaceElevated,
                child: Text(
                  currentEmp?.name.substring(0, 1) ?? 'U',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary),
                ),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      currentEmp?.name ?? 'Employee',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: currentEmp?.isAdmin == true
                            ? AppTheme.primary.withOpacity(0.15)
                            : currentEmp?.isManager == true
                                ? AppTheme.statusYellow.withOpacity(0.15)
                                : AppTheme.statusGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        currentEmp?.role ?? 'Staff',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: currentEmp?.isAdmin == true
                              ? AppTheme.primary
                              : currentEmp?.isManager == true
                                  ? AppTheme.statusYellow
                                  : AppTheme.statusGreen,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: currentEmp?.isClockedIn == true
                            ? AppTheme.statusGreen
                            : AppTheme.statusRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      currentEmp?.isClockedIn == true ? 'Clocked In' : 'Off Shift',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),
                tooltip: 'Lock / Return to Keypad',
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const PinKeypadScreen()),
                  );
                },
              ),
            ],
          ),
          body: IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _navigateToTab,
              type: BottomNavigationBarType.fixed,
              backgroundColor: AppTheme.surface,
              selectedItemColor: AppTheme.primary,
              unselectedItemColor: AppTheme.textMuted,
              selectedFontSize: 11,
              unselectedFontSize: 11,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.table_restaurant_outlined),
                  activeIcon: Icon(Icons.table_restaurant_rounded),
                  label: 'Floor Plan',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.point_of_sale_outlined),
                  activeIcon: Icon(Icons.point_of_sale_rounded),
                  label: 'Quick POS',
                ),
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: kdsCount > 0,
                    label: Text('$kdsCount'),
                    backgroundColor: AppTheme.primary,
                    child: const Icon(Icons.soup_kitchen_outlined),
                  ),
                  activeIcon: Badge(
                    isLabelVisible: kdsCount > 0,
                    label: Text('$kdsCount'),
                    backgroundColor: AppTheme.primary,
                    child: const Icon(Icons.soup_kitchen_rounded),
                  ),
                  label: 'Kitchen (KDS)',
                ),
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: lowStockCount > 0,
                    label: Text('$lowStockCount'),
                    backgroundColor: AppTheme.statusRed,
                    child: const Icon(Icons.inventory_2_outlined),
                  ),
                  activeIcon: Badge(
                    isLabelVisible: lowStockCount > 0,
                    label: Text('$lowStockCount'),
                    backgroundColor: AppTheme.statusRed,
                    child: const Icon(Icons.inventory_2_rounded),
                  ),
                  label: 'Inventory',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.access_time_outlined),
                  activeIcon: Icon(Icons.access_time_filled_rounded),
                  label: 'Shifts',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
